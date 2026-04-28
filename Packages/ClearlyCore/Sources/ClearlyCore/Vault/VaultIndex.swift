import Foundation
import GRDB
import CryptoKit

// MARK: - Record Types

public struct IndexedFile: Equatable {
    public let id: Int64
    public let path: String       // relative to vault root
    public let filename: String   // no extension
    public let contentHash: String
    public let modifiedAt: Date
    public let indexedAt: Date
}

public struct SearchResult {
    public let file: IndexedFile
    public let snippet: String
}

public struct MatchExcerpt {
    public let lineNumber: Int        // 1-based
    public let contextLine: String    // the line containing the match
    public let highlightedContextLine: String
}

public struct SearchFileGroup {
    public let file: IndexedFile
    public let vaultRootURL: URL
    public let matchesFilename: Bool
    public let relevanceRank: Double
    public let excerpts: [MatchExcerpt]
}

public struct LinkRecord {
    public let id: Int64
    public let sourceFileId: Int64
    public let targetName: String
    public let targetFileId: Int64?
    public let lineNumber: Int?
    public let displayText: String?
    public let context: String?
    public let sourceFilename: String?
    public let sourcePath: String?
}

// MARK: - VaultIndex

public final class VaultIndex: @unchecked Sendable {

    private let dbPool: DatabasePool
    public let rootURL: URL

    private let embeddingSweepLock = NSLock()
    private var embeddingSweep: Task<Void, Never>?

    // MARK: Init

    public init(locationURL: URL) throws {
        self.rootURL = locationURL

        let indexDir = Self.indexDirectory()
        try FileManager.default.createDirectory(at: indexDir, withIntermediateDirectories: true)

        let hash = Self.pathHash(locationURL.standardizedFileURL.path)
        let dbPath = indexDir.appendingPathComponent("\(hash).sqlite").path

        dbPool = try DatabasePool(path: dbPath)

        try migrate()
    }

    #if os(macOS)
    /// Init with explicit bundle identifier — used by ClearlyMCP to open the main app's index
    public init(locationURL: URL, bundleIdentifier: String) throws {
        self.rootURL = locationURL

        let indexDir = Self.indexDirectory(bundleIdentifier: bundleIdentifier)
        try FileManager.default.createDirectory(at: indexDir, withIntermediateDirectories: true)

        let hash = Self.pathHash(locationURL.standardizedFileURL.path)
        let dbPath = indexDir.appendingPathComponent("\(hash).sqlite").path

        dbPool = try DatabasePool(path: dbPath)

        try migrate()
    }
    #endif

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

        migrator.registerMigration("v2_embeddings") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS embeddings (
                    file_id INTEGER PRIMARY KEY REFERENCES files(id) ON DELETE CASCADE,
                    content_hash TEXT NOT NULL,
                    model_version INTEGER NOT NULL,
                    vector BLOB NOT NULL,
                    updated_at REAL NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_embeddings_model ON embeddings(model_version)")
        }

        // v3 (2026-04-28): chunked embeddings. The v2 table becomes one-row-per-file legacy;
        // v3 replaces it with one-row-per-chunk so long notes don't dilute their signal in a
        // single mean-pooled vector. Drop existing v2 rows — users re-embed on first launch with
        // the new build via the `embeddingsMissingOrStale` sweep. Companion `chunks_fts`
        // virtual table mirrors the chunk text for FTS5/bm25 keyword search at chunk granularity
        // (the existing `files_fts` is preserved for whole-file search like the sidebar's find UI).
        migrator.registerMigration("v3_chunked_embeddings") { db in
            try db.execute(sql: "DROP TABLE IF EXISTS embeddings")
            try db.execute(sql: """
                CREATE TABLE embeddings (
                    file_id INTEGER NOT NULL REFERENCES files(id) ON DELETE CASCADE,
                    chunk_index INTEGER NOT NULL,
                    chunk_text_offset INTEGER NOT NULL,
                    chunk_text_length INTEGER NOT NULL,
                    heading_path TEXT NOT NULL DEFAULT '[]',
                    content_hash TEXT NOT NULL,
                    model_version INTEGER NOT NULL,
                    vector BLOB NOT NULL,
                    updated_at REAL NOT NULL,
                    PRIMARY KEY (file_id, chunk_index)
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_embeddings_model ON embeddings(model_version)")
            try db.execute(sql: "CREATE INDEX idx_embeddings_file ON embeddings(file_id)")

            try db.execute(sql: """
                CREATE VIRTUAL TABLE chunks_fts USING fts5(
                    chunk_text,
                    file_id UNINDEXED,
                    chunk_index UNINDEXED,
                    tokenize='porter unicode61'
                )
                """)
        }

        try migrator.migrate(dbPool)
    }


    // MARK: Write — Single File

    @discardableResult
    public func updateFile(at relativePath: String) throws -> IndexedFile? {
        let fileURL = rootURL.appendingPathComponent(relativePath)

        return try dbPool.write { db in
            let existingRow = try Row.fetchOne(db, sql: "SELECT id, content_hash FROM files WHERE path = ?", arguments: [relativePath])

            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                if let id: Int64 = existingRow?["id"] {
                    try self.removeIndexedFile(db: db, id: id)
                    try self.resolveWikiLinkTargets(db: db)
                }
                return nil
            }

            guard Limits.isOpenableSize(fileURL) else {
                DiagnosticLog.log("VaultIndex: skipping oversized file \(fileURL.lastPathComponent)")
                if let id: Int64 = existingRow?["id"] {
                    try self.removeIndexedFile(db: db, id: id)
                    try self.resolveWikiLinkTargets(db: db)
                }
                return nil
            }
            guard let data = try? Data(contentsOf: fileURL),
                  let content = String(data: data, encoding: .utf8) else {
                return nil
            }

            let hash = Self.contentHash(data)
            if let existingHash: String = existingRow?["content_hash"], existingHash == hash {
                let row = try Row.fetchOne(db, sql: "SELECT * FROM files WHERE path = ?", arguments: [relativePath])
                return row.map(Self.indexedFile(from:))
            }

            let filename = fileURL.deletingPathExtension().lastPathComponent
            let modDate = Self.fileModDate(fileURL)
            let now = Date()

            if let existingId: Int64 = existingRow?["id"] {
                try db.execute(sql: """
                    UPDATE files SET filename = ?, content_hash = ?, modified_at = ?, indexed_at = ?
                    WHERE id = ?
                    """, arguments: [filename, hash, modDate.timeIntervalSince1970, now.timeIntervalSince1970, existingId])

                try db.execute(sql: "DELETE FROM files_fts WHERE rowid = ?", arguments: [existingId])
                try db.execute(sql: "INSERT INTO files_fts(rowid, filename, content) VALUES(?, ?, ?)",
                               arguments: [existingId, filename, content])

                try db.execute(sql: "DELETE FROM links WHERE source_file_id = ?", arguments: [existingId])
                try db.execute(sql: "DELETE FROM tags WHERE file_id = ?", arguments: [existingId])
                try db.execute(sql: "DELETE FROM headings WHERE file_id = ?", arguments: [existingId])

                self.insertParsedData(db: db, fileId: existingId, content: content)
                try self.resolveWikiLinkTargets(db: db)

                let row = try Row.fetchOne(db, sql: "SELECT * FROM files WHERE id = ?", arguments: [existingId])
                return row.map(Self.indexedFile(from:))
            } else {
                try db.execute(sql: """
                    INSERT INTO files (path, filename, content_hash, modified_at, indexed_at)
                    VALUES (?, ?, ?, ?, ?)
                    """, arguments: [relativePath, filename, hash, modDate.timeIntervalSince1970, now.timeIntervalSince1970])

                let fileId = db.lastInsertedRowID

                try db.execute(sql: "INSERT INTO files_fts(rowid, filename, content) VALUES(?, ?, ?)",
                               arguments: [fileId, filename, content])

                self.insertParsedData(db: db, fileId: fileId, content: content)
                try self.resolveWikiLinkTargets(db: db)

                let row = try Row.fetchOne(db, sql: "SELECT * FROM files WHERE id = ?", arguments: [fileId])
                return row.map(Self.indexedFile(from:))
            }
        }
    }

    public func resolveLinksToFile(named filename: String) throws {
        try dbPool.write { db in
            let lower = filename.lowercased()
            try db.execute(sql: """
                UPDATE links SET target_file_id = (
                    SELECT id FROM files WHERE LOWER(filename) = ? LIMIT 1
                ) WHERE LOWER(target_name) = ? AND target_file_id IS NULL
                """, arguments: [lower, lower])
        }
    }

    // MARK: Write — Full Index

    public func indexAllFiles(showHiddenFiles: Bool = false) {
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

                    guard Limits.isOpenableSize(fileURL) else {
                        DiagnosticLog.log("VaultIndex: skipping oversized file \(fileURL.lastPathComponent)")
                        if let existing = existingByPath[relativePath] {
                            try self.removeIndexedFile(db: db, id: existing.id)
                        }
                        continue
                    }
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
                        try self.removeIndexedFile(db: db, id: existing.id)
                    }
                }

                try self.resolveWikiLinkTargets(db: db)
            }
        } catch {
            DiagnosticLog.log("VaultIndex: indexAllFiles failed — \(error.localizedDescription)")
        }
    }

    /// Async variant with optional per-file placeholder-download hook and progress reporting.
    /// iOS uses the hook to materialize `.icloud` placeholders via `startDownloadingUbiquitousItem`
    /// before parsing. Mac can pass `nil` (equivalent to the sync `indexAllFiles`).
    ///
    /// The hook returns `true` if the file is ready to read, `false` if it should be skipped
    /// (e.g. still a placeholder after a timeout); the watcher will re-drive it via `updateFile`
    /// once the download lands.
    public func indexAllFiles(
        showHiddenFiles: Bool = false,
        downloadPlaceholder: ((URL) async -> Bool)?,
        progress: ((Double) -> Void)?
    ) async {
        let markdownFiles = collectMarkdownFiles(under: rootURL, showHiddenFiles: showHiddenFiles)
        let total = max(markdownFiles.count, 1)

        struct PendingFile {
            let relativePath: String
            let filename: String
            let content: String
            let contentHash: String
            let modifiedAt: Date
        }

        var pending: [PendingFile] = []
        pending.reserveCapacity(markdownFiles.count)
        var processedPaths = Set<String>()

        for (idx, fileURL) in markdownFiles.enumerated() {
            if Task.isCancelled { return }

            let relativePath = Self.relativePath(of: fileURL, from: rootURL)

            var usable = true
            if let hook = downloadPlaceholder {
                usable = await hook(fileURL)
            }

            var retainIndexedPath = true
            if usable, !Limits.isOpenableSize(fileURL) {
                DiagnosticLog.log("VaultIndex: skipping oversized file \(fileURL.lastPathComponent)")
                usable = false
                retainIndexedPath = false
            }

            if retainIndexedPath {
                processedPaths.insert(relativePath)
            }

            if usable,
               let data = try? Data(contentsOf: fileURL),
               let content = String(data: data, encoding: .utf8) {
                pending.append(PendingFile(
                    relativePath: relativePath,
                    filename: fileURL.deletingPathExtension().lastPathComponent,
                    content: content,
                    contentHash: Self.contentHash(data),
                    modifiedAt: Self.fileModDate(fileURL)
                ))
            }

            progress?(Double(idx + 1) / Double(total))
        }

        let fileBatch = pending
        let processed = processedPaths

        do {
            try await dbPool.write { db in
                let existingRows = try Row.fetchAll(db, sql: "SELECT id, path, content_hash FROM files")
                var existingByPath: [String: (id: Int64, hash: String)] = [:]
                for row in existingRows {
                    let path: String = row["path"]
                    let id: Int64 = row["id"]
                    let hash: String = row["content_hash"]
                    existingByPath[path] = (id, hash)
                }

                for file in fileBatch {
                    if let existing = existingByPath[file.relativePath], existing.hash == file.contentHash {
                        continue
                    }

                    let now = Date()

                    if let existing = existingByPath[file.relativePath] {
                        try db.execute(sql: """
                            UPDATE files SET filename = ?, content_hash = ?, modified_at = ?, indexed_at = ?
                            WHERE id = ?
                            """, arguments: [file.filename, file.contentHash, file.modifiedAt.timeIntervalSince1970, now.timeIntervalSince1970, existing.id])

                        try db.execute(sql: "DELETE FROM files_fts WHERE rowid = ?", arguments: [existing.id])
                        try db.execute(sql: "INSERT INTO files_fts(rowid, filename, content) VALUES(?, ?, ?)",
                                       arguments: [existing.id, file.filename, file.content])

                        try db.execute(sql: "DELETE FROM links WHERE source_file_id = ?", arguments: [existing.id])
                        try db.execute(sql: "DELETE FROM tags WHERE file_id = ?", arguments: [existing.id])
                        try db.execute(sql: "DELETE FROM headings WHERE file_id = ?", arguments: [existing.id])

                        self.insertParsedData(db: db, fileId: existing.id, content: file.content)
                    } else {
                        try db.execute(sql: """
                            INSERT INTO files (path, filename, content_hash, modified_at, indexed_at)
                            VALUES (?, ?, ?, ?, ?)
                            """, arguments: [file.relativePath, file.filename, file.contentHash, file.modifiedAt.timeIntervalSince1970, now.timeIntervalSince1970])

                        let fileId = db.lastInsertedRowID

                        try db.execute(sql: "INSERT INTO files_fts(rowid, filename, content) VALUES(?, ?, ?)",
                                       arguments: [fileId, file.filename, file.content])

                        self.insertParsedData(db: db, fileId: fileId, content: file.content)
                    }
                }

                // Remove files that no longer exist on disk (pruned against the enumerated set,
                // not the successfully-read set — placeholders that timed out still count as present).
                let existingPaths = Set(existingByPath.keys)
                let removedPaths = existingPaths.subtracting(processed)
                for path in removedPaths {
                    if let existing = existingByPath[path] {
                        try self.removeIndexedFile(db: db, id: existing.id)
                    }
                }

                try self.resolveWikiLinkTargets(db: db)
            }
        } catch {
            DiagnosticLog.log("VaultIndex: indexAllFiles (async) failed — \(error.localizedDescription)")
        }
    }

    private func resolveWikiLinkTargets(db: Database) throws {
        try db.execute(sql: """
            UPDATE links SET target_file_id = (
                SELECT f.id FROM files f
                WHERE LOWER(f.filename) = LOWER(links.target_name)
                LIMIT 1
            )
            """)
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

    private func removeIndexedFile(db: Database, id: Int64) throws {
        try db.execute(sql: "DELETE FROM files_fts WHERE rowid = ?", arguments: [id])
        try db.execute(sql: "DELETE FROM chunks_fts WHERE file_id = ?", arguments: [id])
        try db.execute(sql: "DELETE FROM embeddings WHERE file_id = ?", arguments: [id])
        try db.execute(sql: "DELETE FROM links WHERE source_file_id = ?", arguments: [id])
        try db.execute(sql: "UPDATE links SET target_file_id = NULL WHERE target_file_id = ?", arguments: [id])
        try db.execute(sql: "DELETE FROM tags WHERE file_id = ?", arguments: [id])
        try db.execute(sql: "DELETE FROM headings WHERE file_id = ?", arguments: [id])
        try db.execute(sql: "DELETE FROM files WHERE id = ?", arguments: [id])
    }

    // MARK: Read — Files

    public func allFiles() -> [IndexedFile] {
        do {
            return try dbPool.read { db in
                try Row.fetchAll(db, sql: "SELECT * FROM files ORDER BY filename")
                    .map(Self.indexedFile(from:))
            }
        } catch {
            return []
        }
    }

    public func searchFiles(query: String) -> [SearchResult] {
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

    /// FTS5 chunk-level ranked search where the supplied keywords are OR'd together with
    /// prefix matching. Used by chat RAG fusion — small mean-pooled embedders silently miss
    /// obvious literal matches (e.g. "local-first software" → `Local-First Software.md`)
    /// when the vault has many similarly-shaped Lorem Ipsum notes; bm25 over chunk text catches
    /// those. Returns chunk-level rows so the retriever can correlate keyword hits to specific
    /// chunks (heading path, etc.) when fusing with cosine. Caller is expected to pre-strip
    /// stopwords and short tokens.
    public func searchByKeywords(
        _ keywords: [String],
        limit: Int = 50,
        modelVersion: Int = EmbeddingService.MODEL_VERSION
    ) -> [ChunkSearchResult] {
        let escaped = keywords
            .map { $0.replacingOccurrences(of: "\"", with: "\"\"") }
            .filter { !$0.isEmpty }
        guard !escaped.isEmpty else { return [] }
        let ftsQuery = escaped.map { "\"\($0)\"*" }.joined(separator: " OR ")

        do {
            return try dbPool.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT chunks_fts.file_id AS file_id,
                           chunks_fts.chunk_index AS chunk_index,
                           f.path AS path,
                           chunks_fts.chunk_text AS chunk_text,
                           snippet(chunks_fts, 0, '<b>', '</b>', '…', 32) AS snippet
                    FROM chunks_fts
                    JOIN files f ON f.id = chunks_fts.file_id
                    JOIN embeddings e ON e.file_id = chunks_fts.file_id
                                     AND e.chunk_index = chunks_fts.chunk_index
                    WHERE chunks_fts MATCH ?
                      AND e.model_version = ?
                      AND e.content_hash = f.content_hash
                    ORDER BY bm25(chunks_fts)
                    LIMIT ?
                    """, arguments: [ftsQuery, modelVersion, limit])

                return rows.map { row in
                    ChunkSearchResult(
                        fileID: row["file_id"],
                        chunkIndex: row["chunk_index"],
                        path: row["path"],
                        chunkText: row["chunk_text"] ?? "",
                        snippet: row["snippet"] ?? ""
                    )
                }
            }
        } catch {
            return []
        }
    }

    public func searchFilesGrouped(query: String) -> [SearchFileGroup] {
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
                    SELECT f.*, highlight(files_fts, 1, '<<', '>>') AS highlighted_content, bm25(files_fts) AS rank
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
                    let relevanceRank: Double = row["rank"] ?? Double.greatestFiniteMagnitude
                    let filenameMatches = searchTerms.contains { file.filename.lowercased().contains($0) }

                    // Find matching lines from FTS-highlighted content so stemmed/tokenized
                    // matches still produce excerpts and scroll targets.
                    let lines = highlightedContent.components(separatedBy: "\n")
                    var excerpts: [MatchExcerpt] = []
                    for (i, line) in lines.enumerated() {
                        if line.contains("<<") {
                            let highlightedLine = Self.truncatedHighlightedLine(line, visibleLimit: 200)
                            excerpts.append(MatchExcerpt(
                                lineNumber: i + 1,
                                contextLine: highlightedLine
                                    .replacingOccurrences(of: "<<", with: "")
                                    .replacingOccurrences(of: ">>", with: ""),
                                highlightedContextLine: highlightedLine
                            ))
                            if excerpts.count >= 5 { break }
                        }
                    }

                    resultsByFileId[file.id] = SearchFileGroup(
                        file: file,
                        vaultRootURL: rootURL,
                        matchesFilename: filenameMatches,
                        relevanceRank: relevanceRank,
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
                                relevanceRank: Double.greatestFiniteMagnitude,
                                excerpts: []
                            )
                            orderedIds.append(file.id)
                        }
                    }
                }

                // Sort deterministically: filename matches first, then BM25 rank, then path.
                let groups = orderedIds.compactMap { resultsByFileId[$0] }
                return groups.sorted { a, b in
                    if a.matchesFilename != b.matchesFilename { return a.matchesFilename }
                    if a.relevanceRank != b.relevanceRank { return a.relevanceRank < b.relevanceRank }
                    return a.file.path.localizedCaseInsensitiveCompare(b.file.path) == .orderedAscending
                }
            }
        } catch {
            return []
        }
    }

    public func resolveWikiLink(name: String) -> IndexedFile? {
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

    public func lineNumberForHeading(in fileId: Int64, heading: String) -> Int? {
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

    public func linksTo(fileId: Int64) -> [LinkRecord] {
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

    public func linksFrom(fileId: Int64) -> [LinkRecord] {
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

    public func unlinkedMentions(for filename: String, excludingFileId: Int64) -> [(file: IndexedFile, lineNumber: Int, contextLine: String)] {
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

    public func allTags() -> [(tag: String, count: Int)] {
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

    public func filesForTag(tag: String) -> [IndexedFile] {
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

    // MARK: Read — Headings by File

    public func headings(forFileId fileId: Int64) -> [ParsedHeading] {
        do {
            return try dbPool.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT text, level, line_number FROM headings
                    WHERE file_id = ?
                    ORDER BY line_number
                    """, arguments: [fileId])
                    .map { row in
                        ParsedHeading(
                            text: row["text"],
                            level: Int(row["level"] as Int64),
                            lineNumber: Int(row["line_number"] as Int64)
                        )
                    }
            }
        } catch {
            return []
        }
    }

    // MARK: Read — Tags by File

    public func tags(forFileId fileId: Int64) -> [String] {
        do {
            return try dbPool.read { db in
                try Row.fetchAll(db, sql: """
                    SELECT DISTINCT tag FROM tags
                    WHERE file_id = ?
                    ORDER BY tag
                    """, arguments: [fileId])
                    .map { $0["tag"] as String }
            }
        } catch {
            return []
        }
    }

    // MARK: Read — Vault Summary

    public func fileCount() -> Int {
        do {
            return try dbPool.read { db in
                let row = try Row.fetchOne(db, sql: "SELECT COUNT(*) AS c FROM files")
                return Int(row?["c"] as Int64? ?? 0)
            }
        } catch {
            return 0
        }
    }

    public func lastIndexedAt() -> Date? {
        do {
            return try dbPool.read { db in
                let row = try Row.fetchOne(db, sql: "SELECT MAX(indexed_at) AS m FROM files")
                guard let ts = row?["m"] as Double? else { return nil }
                return Date(timeIntervalSince1970: ts)
            }
        } catch {
            return nil
        }
    }

    // MARK: Read — File by URL

    public func file(forURL url: URL) -> IndexedFile? {
        let relativePath = Self.relativePath(of: url, from: rootURL)
        return file(forRelativePath: relativePath)
    }

    // MARK: Read — File by path

    public func file(forRelativePath path: String) -> IndexedFile? {
        do {
            return try dbPool.read { db in
                let row = try Row.fetchOne(db, sql: "SELECT * FROM files WHERE path = ?", arguments: [path])
                return row.map(Self.indexedFile(from:))
            }
        } catch {
            return nil
        }
    }

    // MARK: Embeddings

    public struct StaleEmbeddingTarget: Equatable {
        public let fileID: Int64
        public let path: String
        public let contentHash: String
    }

    /// Materialized chunk: caller-supplied input to `upsertChunkEmbeddings`. The `embedText`
    /// (title + heading path + body) is what the embedder sees; `body` is what the LLM context
    /// renderer shows; `headingPath` survives via `StoredChunkEmbedding` for citation rendering.
    public struct ChunkEmbeddingInput {
        public let chunkIndex: Int
        public let textOffset: Int
        public let textLength: Int
        public let headingPath: [String]
        public let body: String
        public let vector: [Float]

        public init(
            chunkIndex: Int,
            textOffset: Int,
            textLength: Int,
            headingPath: [String],
            body: String,
            vector: [Float]
        ) {
            self.chunkIndex = chunkIndex
            self.textOffset = textOffset
            self.textLength = textLength
            self.headingPath = headingPath
            self.body = body
            self.vector = vector
        }
    }

    /// Hydrated chunk row from the `embeddings` + `files` tables. Carries everything the chat
    /// retriever needs to rank, dedupe by file, and render citations with heading context.
    public struct StoredChunkEmbedding: Equatable {
        public let fileID: Int64
        public let chunkIndex: Int
        public let path: String
        public let headingPath: [String]
        public let textOffset: Int
        public let textLength: Int
        public let vector: [Float]
    }

    /// FTS5 chunk-level keyword hit. File path is denormalized through the JOIN with `files`
    /// so the chat retriever can correlate keyword hits to cosine hits without an extra round
    /// trip. `chunkText` is the verbatim body that matched (small enough to inline).
    public struct ChunkSearchResult: Equatable {
        public let fileID: Int64
        public let chunkIndex: Int
        public let path: String
        public let chunkText: String
        public let snippet: String
    }

    /// Upsert all chunks for one file in a single transaction. Atomically deletes any prior
    /// rows for `fileID` (in both `embeddings` and `chunks_fts`) before inserting the new set —
    /// this is how chunk-count changes (e.g. note grew/shrank) propagate cleanly without
    /// orphaned rows. All chunks share the same `contentHash` and `modelVersion`.
    public func upsertChunkEmbeddings(
        fileID: Int64,
        contentHash: String,
        chunks: [ChunkEmbeddingInput],
        modelVersion: Int
    ) throws {
        let now = Date().timeIntervalSince1970
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM embeddings WHERE file_id = ?", arguments: [fileID])
            try db.execute(sql: "DELETE FROM chunks_fts WHERE file_id = ?", arguments: [fileID])
            for chunk in chunks {
                let headingJSON = Self.encodeHeadingPath(chunk.headingPath)
                try db.execute(sql: """
                    INSERT INTO embeddings (
                        file_id, chunk_index, chunk_text_offset, chunk_text_length,
                        heading_path, content_hash, model_version, vector, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [
                        fileID, chunk.chunkIndex, chunk.textOffset, chunk.textLength,
                        headingJSON, contentHash, modelVersion, chunk.vector.blobData, now
                    ])
                try db.execute(sql: """
                    INSERT INTO chunks_fts (file_id, chunk_index, chunk_text)
                    VALUES (?, ?, ?)
                    """, arguments: [fileID, chunk.chunkIndex, chunk.body])
            }
        }
    }

    /// Files that need (re-)chunking + (re-)embedding. A file is stale if it has zero chunks at
    /// the current `modelVersion`, or if any of its chunks has drifted `content_hash`. The
    /// caller re-chunks the entire file when it picks up a stale target — partial re-embeds
    /// would leave the chunk_index space inconsistent.
    public func embeddingsMissingOrStale(modelVersion: Int) throws -> [StaleEmbeddingTarget] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT f.id AS file_id, f.path, f.content_hash
                FROM files f
                WHERE NOT EXISTS (
                    SELECT 1 FROM embeddings e
                    WHERE e.file_id = f.id
                      AND e.model_version = ?
                      AND e.content_hash = f.content_hash
                )
                """, arguments: [modelVersion])
            return rows.map {
                StaleEmbeddingTarget(fileID: $0["file_id"], path: $0["path"], contentHash: $0["content_hash"])
            }
        }
    }

    /// All current chunk embeddings at `modelVersion`. Skips rows whose stored content_hash
    /// has drifted from the file's current hash (those will be replaced by the next sweep).
    /// Used by the chat retriever's cosine ranking.
    public func allChunkEmbeddings(modelVersion: Int) throws -> [StoredChunkEmbedding] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT e.file_id, e.chunk_index, f.path, e.heading_path,
                       e.chunk_text_offset, e.chunk_text_length, e.vector
                FROM embeddings e
                JOIN files f ON f.id = e.file_id
                WHERE e.model_version = ?
                  AND e.content_hash = f.content_hash
                """, arguments: [modelVersion])
            return rows.compactMap { row -> StoredChunkEmbedding? in
                let blob: Data = row["vector"]
                guard let vec = [Float].fromBlobData(blob) else { return nil }
                let headingJSON: String = row["heading_path"]
                return StoredChunkEmbedding(
                    fileID: row["file_id"],
                    chunkIndex: row["chunk_index"],
                    path: row["path"],
                    headingPath: Self.decodeHeadingPath(headingJSON),
                    textOffset: row["chunk_text_offset"],
                    textLength: row["chunk_text_length"],
                    vector: vec
                )
            }
        }
    }

    /// Lookup all chunks for a file. Empty array if none stored.
    public func chunkEmbeddings(forFileID fileID: Int64) throws -> [StoredChunkEmbedding] {
        try dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT e.file_id, e.chunk_index, f.path, e.heading_path,
                       e.chunk_text_offset, e.chunk_text_length, e.vector
                FROM embeddings e
                JOIN files f ON f.id = e.file_id
                WHERE e.file_id = ?
                ORDER BY e.chunk_index
                """, arguments: [fileID])
            return rows.compactMap { row -> StoredChunkEmbedding? in
                let blob: Data = row["vector"]
                guard let vec = [Float].fromBlobData(blob) else { return nil }
                let headingJSON: String = row["heading_path"]
                return StoredChunkEmbedding(
                    fileID: row["file_id"],
                    chunkIndex: row["chunk_index"],
                    path: row["path"],
                    headingPath: Self.decodeHeadingPath(headingJSON),
                    textOffset: row["chunk_text_offset"],
                    textLength: row["chunk_text_length"],
                    vector: vec
                )
            }
        }
    }

    /// Explicit invalidation — clears every chunk row + chunks_fts. Used when the embedder
    /// itself changes (e.g. dimension flip on a future swap) and you'd rather take the hit
    /// up-front than rely on `embeddingsMissingOrStale` to drip-detect.
    public func deleteAllEmbeddings() throws {
        try dbPool.write { db in
            try db.execute(sql: "DELETE FROM embeddings")
            try db.execute(sql: "DELETE FROM chunks_fts")
        }
    }

    private static func encodeHeadingPath(_ path: [String]) -> String {
        guard !path.isEmpty else { return "[]" }
        let data = (try? JSONEncoder().encode(path)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func decodeHeadingPath(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Background sweep that brings the `embeddings` table back in sync with `files`. Idempotent
    /// and cancellable — calling it again interrupts any in-flight sweep so we never pile up
    /// duplicate work. Silent on failure: model-asset downloads, file-read errors, and individual
    /// embed failures are logged via `DiagnosticLog` but never surface to the user.
    ///
    /// Call from the indexer right after `indexAllFiles` completes — the MissingOrStale query
    /// picks up new files, content_hash drift, and `MODEL_VERSION` bumps in one shot.
    public func scheduleEmbeddingRefresh(modelVersion: Int = EmbeddingService.MODEL_VERSION) {
        // Cancel the prior sweep BEFORE creating the new task. Both a) prevents two `Task.detached`
        // bodies from being live at the same time and b) avoids the double-write we'd otherwise see
        // when back-to-back FSEvents bursts call this method.
        embeddingSweepLock.lock()
        embeddingSweep?.cancel()
        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let stale = try self.embeddingsMissingOrStale(modelVersion: modelVersion)
                if stale.isEmpty { return }

                let service: EmbeddingService
                do {
                    service = try EmbeddingService()
                } catch {
                    DiagnosticLog.log("Embedding service init failed: \(error.localizedDescription)")
                    return
                }

                var processed = 0
                var totalChunks = 0
                for target in stale {
                    if Task.isCancelled { return }
                    let fileURL = self.rootURL.appendingPathComponent(target.path)
                    guard Limits.isOpenableSize(fileURL) else {
                        DiagnosticLog.log("VaultIndex embed: skipping oversized file \(fileURL.lastPathComponent)")
                        continue
                    }
                    guard let data = try? Data(contentsOf: fileURL),
                          let content = String(data: data, encoding: .utf8) else { continue }

                    // Chunk first; embed each chunk separately so long notes don't dilute
                    // their signal in a single mean-pooled vector. Title + heading-path
                    // prepended via `embedText` per the contextual-retrieval pattern.
                    let filename = (target.path as NSString).lastPathComponent
                    let chunks = MarkdownChunker.chunk(source: content, filename: filename)
                    if chunks.isEmpty {
                        // Empty / frontmatter-only note. Clear any prior chunks for this file
                        // so a previously-non-empty note doesn't keep stale rows around.
                        try? self.upsertChunkEmbeddings(
                            fileID: target.fileID,
                            contentHash: target.contentHash,
                            chunks: [],
                            modelVersion: modelVersion
                        )
                        continue
                    }

                    do {
                        var inputs: [ChunkEmbeddingInput] = []
                        inputs.reserveCapacity(chunks.count)
                        for chunk in chunks {
                            do {
                                let vector = try service.embed(chunk.embedText)
                                inputs.append(ChunkEmbeddingInput(
                                    chunkIndex: chunk.index,
                                    textOffset: chunk.textOffset,
                                    textLength: chunk.textLength,
                                    headingPath: chunk.headingPath,
                                    body: chunk.body,
                                    vector: vector
                                ))
                            } catch EmbeddingError.emptyText {
                                continue
                            }
                        }
                        // Atomically replace this file's chunks. Skip the upsert if every
                        // chunk failed to embed — leaves the prior state in place rather
                        // than blanking the file out on a transient embed failure.
                        guard !inputs.isEmpty else { continue }
                        try self.upsertChunkEmbeddings(
                            fileID: target.fileID,
                            contentHash: target.contentHash,
                            chunks: inputs,
                            modelVersion: modelVersion
                        )
                        processed += 1
                        totalChunks += inputs.count
                    } catch {
                        DiagnosticLog.log("Embedding failed for \(target.path): \(error.localizedDescription)")
                    }
                }
                if processed > 0 {
                    DiagnosticLog.log("Embedding sweep complete: \(processed)/\(stale.count) notes, \(totalChunks) chunks")
                }
            } catch {
                DiagnosticLog.log("Embedding sweep failed: \(error.localizedDescription)")
            }
        }
        embeddingSweep = task
        embeddingSweepLock.unlock()
    }

    // MARK: Lifecycle

    public func close() {
        // DatabasePool is released when the instance is deallocated.
        // Explicit close not needed for GRDB v7, but we keep this for lifecycle clarity.
    }

    // MARK: Helpers

    private static func indexDirectory() -> URL {
        #if os(iOS)
        // Caches lives inside the iOS app sandbox — never inside the ubiquity container,
        // where SQLite WAL/SHM files would race against iCloud sync. The system may reclaim
        // Caches under disk pressure; next launch rebuilds from vault contents.
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("indexes")
        #else
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appName = Bundle.main.bundleIdentifier ?? "com.sabotage.clearly"
        return dir.appendingPathComponent("\(appName)/indexes")
        #endif
    }

    #if os(macOS)
    /// Index directory for a specific bundle identifier — resolves sandbox container path for non-sandboxed callers (ClearlyMCP CLI)
    private static func indexDirectory(bundleIdentifier: String) -> URL {
        // Try sandbox container path first (where the sandboxed app stores its index)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let containerPath = home
            .appendingPathComponent("Library/Containers/\(bundleIdentifier)/Data/Library/Application Support/\(bundleIdentifier)/indexes")
        if FileManager.default.fileExists(atPath: containerPath.path) {
            return containerPath
        }
        // Fall back to standard Application Support (non-sandboxed or not yet created)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("\(bundleIdentifier)/indexes")
    }
    #endif

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

    private static func truncatedHighlightedLine(_ line: String, visibleLimit: Int) -> String {
        var out = ""
        var visible = 0
        var current = line.startIndex
        var inHighlight = false

        while current < line.endIndex && visible < visibleLimit {
            if line[current...].hasPrefix("<<") {
                if !inHighlight {
                    out += "<<"
                    inHighlight = true
                }
                current = line.index(current, offsetBy: 2)
                continue
            }
            if line[current...].hasPrefix(">>") {
                if inHighlight {
                    out += ">>"
                    inHighlight = false
                }
                current = line.index(current, offsetBy: 2)
                continue
            }

            out.append(line[current])
            visible += 1
            current = line.index(after: current)
        }

        if inHighlight { out += ">>" }
        return out
    }

    public static func relativePath(of fileURL: URL, from rootURL: URL) -> String {
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
        guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey], options: options) else {
            return []
        }

        var rules = IgnoreRules(rootURL: rootURL)
        var files: [URL] = []
        for case let url as URL in enumerator {
            let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            let isDir = resourceValues?.isDirectory ?? false

            if isDir {
                rules.loadNestedGitignore(at: url)
                if rules.shouldIgnore(url: url, isDirectory: true) {
                    enumerator.skipDescendants()
                    continue
                }
                continue
            }

            if rules.shouldIgnore(url: url, isDirectory: false) { continue }
            guard FileNode.markdownExtensions.contains(url.pathExtension.lowercased()) else { continue }
            guard resourceValues?.isRegularFile ?? false else { continue }
            files.append(url)
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
