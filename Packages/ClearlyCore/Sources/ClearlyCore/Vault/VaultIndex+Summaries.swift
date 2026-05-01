import Foundation
import GRDB

/// Drives the Notes-style middle list pane. Pulls path + modified-at +
/// FTS5 content for files inside the given folder and derives a title
/// (first H1, fallback to filename) and a 1-line preview in Swift, all
/// in one read transaction.
extension VaultIndex {

    /// Hard cap on the number of rows the middle list pane will pull from
    /// the index. Bounds the SQL fetch, the FTS5 substring chunk, and the
    /// per-row `extractTitleAndPreview` parse — all of which are O(N) in
    /// folder size. For folders larger than this, modified-* sort is
    /// exactly correct (the N most-recent are in the result); title-* sort
    /// is approximately correct (it's the title-sort of the N
    /// filename-alphabetically-first notes, which matches the visible
    /// title order for the overwhelming majority of vaults where filename
    /// and H1 title agree).
    public static let summariesLimit = 1000

    /// - Parameters:
    ///   - folderRelativePath: Path of the target folder relative to the
    ///     vault root. Pass `""` (or `"/"`) to query the root itself.
    ///     Trailing slashes are stripped.
    ///   - recursive: When `true`, includes notes in nested subdirectories.
    ///     When `false`, only direct children of the folder are returned.
    ///   - sort: Result ordering. SQL handles `modified*` orders directly;
    ///     title orders are computed in Swift after `title` derivation since
    ///     the displayed title may differ from the indexed `filename`.
    public func summaries(
        folderRelativePath: String,
        recursive: Bool,
        sort: NoteListSortOrder
    ) -> [NoteSummary] {
        let normalizedFolder = Self.normalizeFolderPath(folderRelativePath)

        do {
            let raws: [SummaryRow] = try dbPool.read { db in
                let (sql, args) = Self.buildSummariesQuery(
                    folder: normalizedFolder,
                    recursive: recursive,
                    sort: sort
                )
                return try Row.fetchAll(db, sql: sql, arguments: args).map { row in
                    SummaryRow(
                        path: row["path"],
                        filename: row["filename"],
                        modifiedAt: Date(timeIntervalSince1970: row["modified_at"]),
                        contentChunk: row["content_chunk"] ?? ""
                    )
                }
            }

            let summaries = raws.map { raw -> NoteSummary in
                let url = rootURL.appendingPathComponent(raw.path)
                let (title, preview) = Self.extractTitleAndPreview(
                    content: raw.contentChunk,
                    fallbackTitle: raw.filename
                )
                return NoteSummary(
                    url: url,
                    title: title,
                    modifiedAt: raw.modifiedAt,
                    preview: preview
                )
            }

            // SQL handles modified-* sorting; title-* needs the derived title.
            switch sort {
            case .modifiedDesc, .modifiedAsc:
                return summaries
            case .titleAsc:
                return summaries.sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            case .titleDesc:
                return summaries.sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending
                }
            }
        } catch {
            DiagnosticLog.log("VaultIndex.summaries failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Internals

    private struct SummaryRow {
        let path: String
        let filename: String
        let modifiedAt: Date
        let contentChunk: String
    }

    /// Builds the SQL + bound arguments. Path filters use `LIKE` patterns:
    ///
    /// - root + recursive  → no path filter
    /// - root + flat       → `path NOT LIKE '%/%'` (top-level files only)
    /// - subfolder + recursive → `path LIKE 'sub/%'`
    /// - subfolder + flat      → `path LIKE 'sub/%' AND path NOT LIKE 'sub/%/%'`
    ///
    /// We `substr(content, 1, 1024)` rather than fetching the full FTS5
    /// content column — preview extraction only needs the first chunk, and
    /// 1k bytes covers frontmatter + a generous lookahead for the first
    /// non-empty body line on every realistic note.
    private static func buildSummariesQuery(
        folder: String,
        recursive: Bool,
        sort: NoteListSortOrder
    ) -> (String, StatementArguments) {
        var conditions: [String] = []
        var args: [DatabaseValueConvertible] = []

        if folder.isEmpty {
            if !recursive {
                conditions.append("f.path NOT LIKE '%/%'")
            }
        } else {
            let prefix = folder + "/"
            conditions.append("f.path LIKE ?")
            args.append(prefix + "%")
            if !recursive {
                conditions.append("f.path NOT LIKE ?")
                args.append(prefix + "%/%")
            }
        }

        let whereClause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"

        let orderClause: String
        switch sort {
        case .modifiedDesc: orderClause = "ORDER BY f.modified_at DESC"
        case .modifiedAsc: orderClause = "ORDER BY f.modified_at ASC"
        case .titleAsc, .titleDesc:
            // Pre-sort by filename in SQL so the post-sort in Swift is
            // already mostly ordered (stable + cheap on near-sorted input).
            orderClause = "ORDER BY f.filename COLLATE NOCASE ASC"
        }

        let sql = """
            SELECT f.path AS path,
                   f.filename AS filename,
                   f.modified_at AS modified_at,
                   substr(files_fts.content, 1, 1024) AS content_chunk
            FROM files f
            JOIN files_fts ON files_fts.rowid = f.id
            \(whereClause)
            \(orderClause)
            LIMIT \(VaultIndex.summariesLimit)
            """

        return (sql, StatementArguments(args))
    }

    private static func normalizeFolderPath(_ raw: String) -> String {
        var path = raw
        while path.hasPrefix("/") { path.removeFirst() }
        while path.hasSuffix("/") { path.removeLast() }
        return path
    }

    /// Drops YAML frontmatter (between leading `---` fences), then walks
    /// the remaining lines: if the first non-empty line is `# Heading`,
    /// that's the title and the next non-empty line is the preview.
    /// Otherwise the title falls back to the filename and the first
    /// non-empty line becomes the preview. Preview is trimmed and capped
    /// at 200 characters to keep List rows snappy.
    static func extractTitleAndPreview(
        content: String,
        fallbackTitle: String
    ) -> (title: String, preview: String) {
        let body = stripFrontmatter(content)

        var title = fallbackTitle
        var preview = ""
        var seenH1 = false

        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // ATX H1 ("# Heading") → title. "## " or deeper headings count
            // as preview-eligible body content.
            if !seenH1, line.hasPrefix("# "), !line.hasPrefix("## ") {
                let derived = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !derived.isEmpty {
                    title = derived
                }
                seenH1 = true
                continue
            }

            // Skip Setext-style underlines that sometimes follow an H1.
            if line.allSatisfy({ $0 == "=" }) || line.allSatisfy({ $0 == "-" }) {
                continue
            }

            preview = String(line.prefix(200))
            break
        }

        return (title, preview)
    }

    /// Strips a single leading YAML/TOML frontmatter block, if present.
    /// Conservative — we look at the first 50 lines only and bail if a
    /// closing fence isn't found (a `---` rule near the top of the body
    /// would otherwise eat content). Returns the original content
    /// untouched when no frontmatter is detected.
    private static func stripFrontmatter(_ content: String) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first else { return content }
        let firstTrim = first.trimmingCharacters(in: .whitespaces)
        guard firstTrim == "---" || firstTrim == "+++" else { return content }
        let fence = firstTrim
        let scanLimit = min(lines.count, 50)
        for index in 1..<scanLimit {
            if lines[index].trimmingCharacters(in: .whitespaces) == fence {
                let remaining = lines.dropFirst(index + 1)
                return remaining.joined(separator: "\n")
            }
        }
        return content
    }
}
