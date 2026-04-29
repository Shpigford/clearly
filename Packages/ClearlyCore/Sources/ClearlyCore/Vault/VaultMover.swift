import Foundation

/// Vault-aware file move. Handles the bookkeeping that a plain
/// `FileManager.moveItem` doesn't:
///
/// 1. Rewrites every `[[wiki-link]]` in inbound source files to point at
///    the new path (preserving heading anchors and aliases).
/// 2. Moves the source file via the file coordinator.
/// 3. Updates the SQLite index, preserving the file's `id` so existing
///    inbound `links.target_file_id` rows survive the move.
/// 4. Reindexes every rewritten source so the `links` table reflects
///    the new wiki-link text.
///
/// Used by both the MCP `move_note` tool and the Mac GUI sidebar rename
/// path so the two surfaces stay consistent.
public enum VaultMover {
    public struct Outcome: Equatable {
        public struct Rewrite: Equatable {
            public let relativePath: String
            public let count: Int
            public init(relativePath: String, count: Int) {
                self.relativePath = relativePath
                self.count = count
            }
        }
        public let linksRewritten: [Rewrite]
        public init(linksRewritten: [Rewrite]) {
            self.linksRewritten = linksRewritten
        }
    }

    public enum MoveError: Error {
        case sourceNotIndexed(String)
    }

    /// Apply the move. Caller is responsible for path validation —
    /// `oldRelativePath` and `newRelativePath` must already be confirmed
    /// vault-relative and safe (no traversal, no absolute paths).
    /// Filesystem move + index update happen unconditionally; if the
    /// caller has already moved the file (e.g. legacy `FileManager`
    /// callers being migrated incrementally), pass `skipFilesystemMove`
    /// and only the index/link bookkeeping runs.
    @discardableResult
    public static func move(
        index: VaultIndex,
        vaultRootURL: URL,
        oldRelativePath: String,
        newRelativePath: String,
        skipFilesystemMove: Bool = false
    ) throws -> Outcome {
        guard let sourceFile = index.file(forRelativePath: oldRelativePath) else {
            throw MoveError.sourceNotIndexed(oldRelativePath)
        }

        // 1. Rewrite inbound wiki-links in every source file.
        let inbound = index.linksTo(fileId: sourceFile.id)
        let inboundSourcePaths = Set(inbound.compactMap { $0.sourcePath })
        var rewrites: [Outcome.Rewrite] = []
        for sourcePath in inboundSourcePaths {
            let url = vaultRootURL.appendingPathComponent(sourcePath)
            let data: Data
            do { data = try CoordinatedFileIO.read(at: url) } catch { continue }
            guard let content = String(data: data, encoding: .utf8) else { continue }
            let result = WikiLinkRewriter.rewrite(content: content, oldTarget: oldRelativePath, newTarget: newRelativePath)
            guard result.count > 0 else { continue }
            try CoordinatedFileIO.write(Data(result.newContent.utf8), to: url)
            rewrites.append(Outcome.Rewrite(relativePath: sourcePath, count: result.count))
        }

        // 2. Move the file itself (unless caller already did it).
        if !skipFilesystemMove {
            let sourceURL = vaultRootURL.appendingPathComponent(oldRelativePath)
            let destURL = vaultRootURL.appendingPathComponent(newRelativePath)
            let destParent = destURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: destParent, withIntermediateDirectories: true)
            try CoordinatedFileIO.move(from: sourceURL, to: destURL)
        }

        // 3. Update the index — preserves file_id.
        try index.moveFile(fromPath: oldRelativePath, toPath: newRelativePath)

        // 4. Reindex every rewritten source.
        for rewrite in rewrites {
            try index.updateFile(at: rewrite.relativePath)
        }

        return Outcome(linksRewritten: rewrites)
    }
}
