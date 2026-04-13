import Foundation
import GRDB
import CryptoKit

// MARK: - Record Types

struct IndexedFile: Equatable {
    let id: Int64
    let path: String       // relative to vault root
    let filename: String   // no extension
    let contentHash: String
    let modifiedAt: Date
    let indexedAt: Date
}

struct SearchResult {
    let file: IndexedFile
    let snippet: String
}

struct MatchExcerpt {
    let lineNumber: Int        // 1-based
    let contextLine: String    // the line containing the match
}

struct SearchFileGroup {
    let file: IndexedFile
    let vaultRootURL: URL
    let matchesFilename: Bool
    let excerpts: [MatchExcerpt]
}

struct LinkRecord {
    let id: Int64
    let sourceFileId: Int64
    let targetName: String
    let targetFileId: Int64?
    let lineNumber: Int?
    let displayText: String?
    let context: String?
    let sourceFilename: String?
    let sourcePath: String?
}

// MARK: - VaultIndex

final class VaultIndex {

    private let dbPool: DatabasePool
    let rootURL: URL

    // MARK: Init

    init(locationURL: URL) throws {
        self.rootURL = locationURL

        let indexDir = Self.indexDirectory()
        try FileManager.default.createDirectory(at: indexDir, withIntermediateDirectories: true)

        let hash = Self.pathHash(locationURL.standardizedFileURL.path)
        let dbPath = indexDir.appendingPathComponent("\(hash).sqlite").path

        dbPool = try DatabasePool(path: dbPath)

        try migrate()
    }

    // MARK: Schema

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS files (
                    id INTEGER PRIMARY KEY,
                    path TEXT UNIQUE NOT NULL,
                    filename TEXT NOT NULL,
                    content_hash TEXT NOT NULL,
                    modified_at REAL NOT NULL,
                    indexed_at REAL NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS files_fts USING fts5(
                    filename,
                    content,
                    tokenize='porter unicode61'
                )
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS links (
                    id INTEGER PRIMARY KEY,
                    source_file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
                    target_name TEXT NOT NULL,
                    target_file_id INTEGER REFERENCES files(id) ON DELETE SET NULL,
                    line_number INTEGER,
                    display_text TEXT,
                    context TEXT
                )
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS tags (
                    id INTEGER PRIMARY KEY,
                    file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
                    tag TEXT NOT NULL,
                    line_number INTEGER,
                    source TEXT NOT NULL DEFAULT 'inline'
                )
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS headings (
                    id INTEGER PRIMARY KEY,
                    file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
                    text TEXT NOT NULL,
                    level INTEGER NOT NULL,
                    line_number INTEGER NOT NULL
                )
                """)

            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_tags_tag ON tags(tag)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_tags_file ON tags(file_id)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_links_source ON links(source_file_id)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_links_target_name ON links(target_name)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_links_target_file ON links(target_file_id)")
        }

        try migrator.migrate(dbPool)
    }

    // MARK: Write — Full Index

    func indexAllFiles(showHiddenFiles: Bool = false) {
        let markdownFiles = collectMarkdownFiles(under: rootURL, showHiddenFiles: showHiddenFiles)

        do {
            try dbPool.write { db in
                // Get existing files for hash comparison
                let existingRows = try Row.fetchAll(db, sql: "SELECT id, path, content_hash FROM files")
                var existingByPath: [String: (id: Int64, hash: String)] = [:]
                for row in existingRows {
                    let path: String = row["path"]
                    let id: Int64 = row["id"]
                    let hash: String = row["content_hash"]
                    existingByPath[path] = (id, hash)
                }

                var processedPaths = Set<String>()

                for fileURL in markdownFiles {
                    let relativePath = Self.relativePath(of: fileURL, from: rootURL)
                    processedPaths.insert(relativePath)

                    guard let data = try? Data(contentsOf: fileURL),
                          let content = String(data: data, encoding: .utf8) else { continue }

                    let hash = Self.contentHash(data)

                    // Skip unchanged files
                    if let existing = existingByPath[relativePath], existing.hash == hash {
                        continue
                    }

                    let filename = fileURL.deletingPathExtension().lastPathComponent
                    let modDate = Self.fileModDate(fileURL)
                    let now = Date()

                    if let existing = existingByPath[relativePath] {
                        // Update existing file
                        try db.execute(sql: """
                            UPDATE files SET filename = ?, content_hash = ?, modified_at = ?, indexed_at = ?
                            WHERE id = ?
                            """, arguments: [filename, hash, modDate.timeIntervalSince1970, now.timeIntervalSince1970, existing.id])

                        // Sync FTS (delete old, insert new)
                        try db.execute(sql: "DELETE FROM files_fts WHERE rowid = ?", arguments: [existing.id])
                        try db.execute(sql: "INSERT INTO files_fts(rowid, filename, content) VALUES(?, ?, ?)",
                                       arguments: [existing.id, filename, content])

                        // Clear old parsed data
                        try db.execute(sql: "DELETE FROM links WHERE source_file_id = ?", arguments: [existing.id])
                        try db.execute(sql: "DELETE FROM tags WHERE file_id = ?", arguments: [existing.id])
                        try db.execute(sql: "DELETE FROM headings WHERE file_id = ?", arguments: [existing.id])

                        insertParsedData(db: db, fileId: existing.id, content: content)
                    } else {
                        // Insert new file
                        try db.execute(sql: """
                            INSERT INTO files (path, filename, content_hash, modified_at, indexed_at)
                            VALUES (?, ?, ?, ?, ?)
                            """, arguments: [relativePath, filename, hash, modDate.timeIntervalSince1970, now.timeIntervalSince1970])

                        let fileId = db.lastInsertedRowID

                        // Sync FTS
                        try db.execute(sql: "INSERT INTO files_fts(rowid, filename, content) VALUES(?, ?, ?)",
                                       arguments: [fileId, filename, content])

                        insertParsedData(db: db, fileId: fileId, content: content)
                    }
                }

                // Remove files that no longer exist on disk
                let existingPaths = Set(existingByPath.keys)
                let removedPaths = existingPaths.subtracting(processedPaths)
                for path in removedPaths {
                    if let existing = existingByPath[path] {
                        try db.execute(sql: "DELETE FROM files_fts WHERE rowid = ?", arguments: [existing.id])
                        try db.execute(sql: "DELETE FROM files WHERE id = ?", arguments: [existing.id])
                    }
                }

                // Resolve wiki-link targets
                try db.execute(sql: """
                    UPDATE links SET target_file_id = (
                        SELECT f.id FROM files f
                        WHERE LOWER(f.filename) = LOWER(links.target_name)
                        LIMIT 1
                    )
                    """)
            }
        } catch {
            DiagnosticLog.log("VaultIndex: indexAllFiles failed — \(error.localizedDescription)")
        }
    }

    private func insertParsedData(db: Database, fileId: Int64, content: String) {
        let parsed = FileParser.parse(content: content)

        for link in parsed.links {
            try? db.execute(sql: """
                INSERT INTO links (source_file_id, target_name, line_number, display_text)
                VALUES (?, ?, ?, ?)
                """, arguments: [fileId, link.target, link.lineNumber, link.alias])
        }

        for tag in parsed.tags {
            try? db.execute(sql: """
                INSERT INTO tags (file_id, tag, line_number, source)
                VALUES (?, ?, ?, ?)
                """, arguments: [fileId, tag.name, tag.lineNumber, tag.source.rawValue])
        }

        for heading in parsed.headings {
            try? db.execute(sql: """
                INSERT INTO headings (file_id, text, level, line_number)
                VALUES (?, ?, ?, ?)
                """, arguments: [fileId, heading.text, heading.level, heading.lineNumber])
        }
    }

    // MARK: Read — Files

    func allFiles() -> [IndexedFile] {
        do {
            return try dbPool.read { db in
                try Row.fetchAll(db, sql: "SELECT * FROM files ORDER BY filename")
                    .map(Self.indexedFile(from:))
            }
        } catch {
            return []
        }
    }

    func searchFiles(query: String) -> [SearchResult] {
        guard !query.isEmpty else { return [] }

        // Escape FTS5 special characters and add prefix matching
        let sanitized = query
            .replacingOccurrences(of: "\"", with: "\"\"")
        let ftsQuery = sanitized
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .map { "\"\($0)\"*" }
            .joined(separator: " ")

        guard !ftsQuery.isEmpty else { return [] }

        do {
            return try dbPool.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT f.*, snippet(files_fts, 1, '<b>', '</b>', '…', 32) AS snippet
                    FROM files_fts
                    JOIN files f ON f.id = files_fts.rowid
                    WHERE files_fts MATCH ?
                    ORDER BY bm25(files_fts)
                    LIMIT 50
                    """, arguments: [ftsQuery])

                return rows.map { row in
                    SearchResult(
                        file: Self.indexedFile(from: row),
                        snippet: row["snippet"] ?? ""
                    )
                }
            }
        } catch {
            return []
        }
    }

    func searchFilesGrouped(query: String) -> [SearchFileGroup] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        // Parse quoted phrases and bare terms
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        var ftsTerms: [String] = []
        var searchTerms: [String] = [] // plain terms for line matching

        let quoteRegex = try! NSRegularExpression(pattern: #""([^"]+)""#)
        let matches = quoteRegex.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed))
        var coveredRanges = Set<Range<String.Index>>()

        for match in matches {
            if let range = Range(match.range(at: 1), in: trimmed) {
                let phrase = String(trimmed[range])
                ftsTerms.append("\"\(phrase.replacingOccurrences(of: "\"", with: "\"\""))\"")
                searchTerms.append(phrase.lowercased())
                coveredRanges.insert(Range(match.range, in: trimmed)!)
            }
        }

        // Bare (unquoted) terms
        var remaining = trimmed
        for range in coveredRanges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            remaining.removeSubrange(range)
        }
        for word in remaining.components(separatedBy: .whitespaces) where !word.isEmpty {
            let escaped = word.replacingOccurrences(of: "\"", with: "\"\"")
            ftsTerms.append("\"\(escaped)\"*")
            searchTerms.append(word.lowercased())
        }

        guard !ftsTerms.isEmpty else { return [] }
        let ftsQuery = ftsTerms.joined(separator: " ")

        do {
            return try dbPool.read { db in
                // FTS5 content search
                let contentRows = try Row.fetchAll(db, sql: """
                    SELECT f.*, highlight(files_fts, 1, '<<', '>>') AS highlighted_content
                    FROM files_fts
                    JOIN files f ON f.id = files_fts.rowid
                    WHERE files_fts MATCH ?
                    ORDER BY bm25(files_fts)
                    LIMIT 50
                    """, arguments: [ftsQuery])

                var resultsByFileId: [Int64: SearchFileGroup] = [:]
                var orderedIds: [Int64] = []

                for row in contentRows {
                    let file = Self.indexedFile(from: row)
                    let highlightedContent: String = row["highlighted_content"] ?? ""
                    let filenameMatches = searchTerms.contains { file.filename.lowercased().contains($0) }

                    // Find matching lines from FTS-highlighted content so stemmed/tokenized
                    // matches still produce excerpts and scroll targets.
                    let lines = highlightedContent.components(separatedBy: "\n")
                    var excerpts: [MatchExcerpt] = []
                    for (i, line) in lines.enumerated() {
                        if line.contains("<<") {
                            excerpts.append(MatchExcerpt(
                                lineNumber: i + 1,
                                contextLine: String(
                                    line
                                        .replacingOccurrences(of: "<<", with: "")
                                        .replacingOccurrences(of: ">>", with: "")
                                        .prefix(200)
                                )
                            ))
                            if excerpts.count >= 5 { break }
                        }
                    }

                    resultsByFileId[file.id] = SearchFileGroup(
                        file: file,
                        vaultRootURL: rootURL,
                        matchesFilename: filenameMatches,
                        excerpts: excerpts
                    )
                    orderedIds.append(file.id)
                }

                // Filename-only matches (not already in content results)
                let existingIds = Set(orderedIds)
                for term in searchTerms {
                    let likePattern = "%\(term)%"
                    let nameRows = try Row.fetchAll(db, sql: """
                        SELECT * FROM files
                        WHERE LOWER(filename) LIKE LOWER(?)
                        LIMIT 20
                        """, arguments: [likePattern])
                    for row in nameRows {
                        let file = Self.indexedFile(from: row)
                        guard !existingIds.contains(file.id) else { continue }
                        if resultsByFileId[file.id] == nil {
                            resultsByFileId[file.id] = SearchFileGroup(
                                file: file,
                                vaultRootURL: self.rootURL,
                                matchesFilename: true,
                                excerpts: []
                            )
                            orderedIds.append(file.id)
                        }
                    }
                }

                // Sort: filename matches first, then content-only, preserving bm25 order within
                let groups = orderedIds.compactMap { resultsByFileId[$0] }
                return groups.sorted { a, b in
                    if a.matchesFilename != b.matchesFilename { return a.matchesFilename }
                    return false // preserve bm25 order
                }
            }
        } catch {
            return []
        }
    }

    func resolveWikiLink(name: String) -> IndexedFile? {
        let normalizedName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        guard !normalizedName.isEmpty else { return nil }

        do {
            return try dbPool.read { db in
                let pathCandidates: [String]
                if normalizedName.contains("/") {
                    let alreadyHasExtension = FileNode.markdownExtensions.contains((normalizedName as NSString).pathExtension.lowercased())
                    if alreadyHasExtension {
                        pathCandidates = [normalizedName]
                    } else {
                        pathCandidates = [normalizedName] + FileNode.markdownExtensions.map { "\(normalizedName).\($0)" }
                    }

                    for candidate in pathCandidates {
                        let row = try Row.fetchOne(db, sql: """
                            SELECT * FROM files
                            WHERE LOWER(path) = LOWER(?)
                            LIMIT 1
                            """, arguments: [candidate])
                        if let row {
                            return Self.indexedFile(from: row)
                        }
                    }
                }

                // Case-insensitive match by filename, prefer shortest path for disambiguation
                let row = try Row.fetchOne(db, sql: """
                    SELECT * FROM files
                    WHERE LOWER(filename) = LOWER(?)
                    ORDER BY LENGTH(path) ASC
                    LIMIT 1
                    """, arguments: [normalizedName])
                return row.map(Self.indexedFile(from:))
            }
        } catch {
            return nil
        }
    }

    func lineNumberForHeading(in fileId: Int64, heading: String) -> Int? {
        let normalized = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        do {
            return try dbPool.read { db in
                let row = try Row.fetchOne(db, sql: """
                    SELECT line_number FROM headings
                    WHERE file_id = ? AND LOWER(text) = LOWER(?)
                    ORDER BY line_number
                    LIMIT 1
                    """, arguments: [fileId, normalized])
                return row?["line_number"]
            }
        } catch {
            return nil
        }
    }

    // MARK: Read — Links

    func linksTo(fileId: Int64) -> [LinkRecord] {
        do {
            return try dbPool.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT l.*, f.filename AS source_filename, f.path AS source_path
                    FROM links l
                    JOIN files f ON l.source_file_id = f.id
                    WHERE l.target_file_id = ?
                    ORDER BY f.filename
                    """, arguments: [fileId])
                    .map(Self.linkRecord(from:))
            }
        } catch {
            return []
        }
    }

    func linksFrom(fileId: Int64) -> [LinkRecord] {
        do {
            return try dbPool.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT l.*, NULL AS source_filename, NULL AS source_path
                    FROM links l
                    WHERE l.source_file_id = ?
                    ORDER BY l.target_name
                    """, arguments: [fileId])
                    .map(Self.linkRecord(from:))
            }
        } catch {
            return []
        }
    }

    // MARK: Read — Unlinked Mentions

    func unlinkedMentions(for filename: String, excludingFileId: Int64) -> [(file: IndexedFile, lineNumber: Int, contextLine: String)] {
        guard filename.count >= 3 else { return [] }

        do {
            return try dbPool.read { db in
                // FTS5 phrase search for the filename
                let ftsQuery = "\"\(filename.replacingOccurrences(of: "\"", with: "\"\""))\""
                let rows = try Row.fetchAll(db, sql: """
                    SELECT f.*, files_fts.content AS raw_content
                    FROM files_fts
                    JOIN files f ON f.id = files_fts.rowid
                    WHERE files_fts MATCH ? AND f.id != ?
                    LIMIT 30
                    """, arguments: [ftsQuery, excludingFileId])

                let wikiLinkPattern = try NSRegularExpression(pattern: "\\[\\[[^\\]]*\\]\\]")
                let lowerFilename = filename.lowercased()
                var results: [(file: IndexedFile, lineNumber: Int, contextLine: String)] = []

                for row in rows {
                    let file = Self.indexedFile(from: row)
                    guard let content = row["raw_content"] as? String else { continue }

                    let lines = content.components(separatedBy: "\n")
                    for (index, line) in lines.enumerated() {
                        guard line.lowercased().contains(lowerFilename) else { continue }

                        // Check if ALL occurrences of filename on this line are inside [[...]]
                        let nsLine = line as NSString
                        let wikiRanges = wikiLinkPattern.matches(in: line, range: NSRange(location: 0, length: nsLine.length)).map(\.range)

                        // Find all occurrences of filename in the line
                        var searchStart = line.startIndex
                        var hasUnlinkedOccurrence = false
                        while let range = line.range(of: filename, options: .caseInsensitive, range: searchStart..<line.endIndex) {
                            let charRange = NSRange(range, in: line)
                            let isInsideWikiLink = wikiRanges.contains { $0.location <= charRange.location && NSMaxRange($0) >= NSMaxRange(charRange) }
                            if !isInsideWikiLink {
                                hasUnlinkedOccurrence = true
                                break
                            }
                            searchStart = range.upperBound
                        }

                        if hasUnlinkedOccurrence {
                            results.append((file: file, lineNumber: index + 1, contextLine: line.trimmingCharacters(in: .whitespaces)))
                            if results.count >= 20 { return results }
                            break // One mention per file is enough
                        }
                    }
                }
                return results
            }
        } catch {
            return []
        }
    }

    // MARK: Read — Tags

    func allTags() -> [(tag: String, count: Int)] {
        do {
            return try dbPool.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT tag, COUNT(DISTINCT file_id) AS cnt
                    FROM tags
                    GROUP BY tag
                    ORDER BY tag
                    """)
                    .map { (tag: $0["tag"] as String, count: Int($0["cnt"] as Int64)) }
            }
        } catch {
            return []
        }
    }

    func filesForTag(tag: String) -> [IndexedFile] {
        do {
            return try dbPool.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT f.* FROM files f
                    JOIN tags t ON t.file_id = f.id
                    WHERE LOWER(t.tag) = LOWER(?)
                    GROUP BY f.id
                    ORDER BY f.filename
                    """, arguments: [tag])
                    .map(Self.indexedFile(from:))
            }
        } catch {
            return []
        }
    }

    // MARK: Read — File by URL

    func file(forURL url: URL) -> IndexedFile? {
        let relativePath = Self.relativePath(of: url, from: rootURL)
        return file(forRelativePath: relativePath)
    }

    // MARK: Read — File by path

    func file(forRelativePath path: String) -> IndexedFile? {
        do {
            return try dbPool.read { db in
                let row = try Row.fetchOne(db, sql: "SELECT * FROM files WHERE path = ?", arguments: [path])
                return row.map(Self.indexedFile(from:))
            }
        } catch {
            return nil
        }
    }

    // MARK: Lifecycle

    func close() {
        // DatabasePool is released when the instance is deallocated.
        // Explicit close not needed for GRDB v7, but we keep this for lifecycle clarity.
    }

    // MARK: Helpers

    private static func indexDirectory() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appName = Bundle.main.bundleIdentifier ?? "com.sabotage.clearly"
        return dir.appendingPathComponent("\(appName)/indexes")
    }

    private static func pathHash(_ path: String) -> String {
        let data = Data(path.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private static func contentHash(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func fileModDate(_ url: URL) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? Date()
    }

    static func relativePath(of fileURL: URL, from rootURL: URL) -> String {
        let filePath = fileURL.standardizedFileURL.path
        let rootPath = rootURL.standardizedFileURL.path
        if filePath.hasPrefix(rootPath) {
            var relative = String(filePath.dropFirst(rootPath.count))
            if relative.hasPrefix("/") { relative = String(relative.dropFirst()) }
            return relative
        }
        return filePath
    }

    private func collectMarkdownFiles(under rootURL: URL, showHiddenFiles: Bool) -> [URL] {
        let fm = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]
        guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: options) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            guard let isFile = try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isFile else { continue }
            if FileNode.markdownExtensions.contains(url.pathExtension.lowercased()) {
                files.append(url)
            }
        }
        return files
    }

    private static func indexedFile(from row: Row) -> IndexedFile {
        IndexedFile(
            id: row["id"],
            path: row["path"],
            filename: row["filename"],
            contentHash: row["content_hash"],
            modifiedAt: Date(timeIntervalSince1970: row["modified_at"]),
            indexedAt: Date(timeIntervalSince1970: row["indexed_at"])
        )
    }

    private static func linkRecord(from row: Row) -> LinkRecord {
        LinkRecord(
            id: row["id"],
            sourceFileId: row["source_file_id"],
            targetName: row["target_name"],
            targetFileId: row["target_file_id"],
            lineNumber: row["line_number"],
            displayText: row["display_text"],
            context: row["context"],
            sourceFilename: row["source_filename"],
            sourcePath: row["source_path"]
        )
    }
}
