import Foundation

/// Vault-aware file move. Handles the bookkeeping that a plain
/// `FileManager.moveItem` doesn't:
///
/// 1. Precomputes every inbound `[[wiki-link]]` rewrite in memory.
/// 2. Moves the source file via the file coordinator.
/// 3. Updates the SQLite index, preserving the file's `id` so existing
///    inbound `links.target_file_id` rows survive the move.
/// 4. Writes rewritten sources and reindexes them.
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
        case destinationExists(String)
    }

    private struct PreparedRewrite {
        let relativePath: String
        let newContent: String
        let count: Int
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

        let sourceURL = vaultRootURL.appendingPathComponent(oldRelativePath)
        let destURL = vaultRootURL.appendingPathComponent(newRelativePath)
        if !skipFilesystemMove {
            if FileManager.default.fileExists(atPath: destURL.path) {
                throw MoveError.destinationExists(newRelativePath)
            }
            try FileManager.default.createDirectory(
                at: destURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }

        // 1. Precompute inbound wiki-link rewrites without touching disk.
        let inbound = index.linksTo(fileId: sourceFile.id)
        let inboundSourcePaths = Set(inbound.compactMap { $0.sourcePath })
        var prepared: [PreparedRewrite] = []
        for sourcePath in inboundSourcePaths {
            let readPath = (skipFilesystemMove && sourcePath == oldRelativePath) ? newRelativePath : sourcePath
            let url = vaultRootURL.appendingPathComponent(readPath)
            let data: Data
            do { data = try CoordinatedFileIO.read(at: url) } catch { continue }
            guard let content = String(data: data, encoding: .utf8) else { continue }
            let result = WikiLinkRewriter.rewrite(content: content, oldTarget: oldRelativePath, newTarget: newRelativePath)
            guard result.count > 0 else { continue }
            let writePath = sourcePath == oldRelativePath ? newRelativePath : sourcePath
            prepared.append(PreparedRewrite(
                relativePath: writePath,
                newContent: result.newContent,
                count: result.count
            ))
        }

        // 2. Move the file itself (unless caller already did it).
        if !skipFilesystemMove {
            try CoordinatedFileIO.move(from: sourceURL, to: destURL)
        }

        // 3. Update the index — preserves file_id.
        do {
            try index.moveFile(fromPath: oldRelativePath, toPath: newRelativePath)
        } catch {
            if !skipFilesystemMove {
                try? CoordinatedFileIO.move(from: destURL, to: sourceURL)
            }
            throw error
        }

        // 4. Write and reindex every rewritten source. Self-links in the
        // moved file are now written/reindexed at the destination path.
        var rewrites: [Outcome.Rewrite] = []
        for rewrite in prepared {
            let url = vaultRootURL.appendingPathComponent(rewrite.relativePath)
            try CoordinatedFileIO.write(Data(rewrite.newContent.utf8), to: url)
            try index.updateFile(at: rewrite.relativePath)
            rewrites.append(Outcome.Rewrite(relativePath: rewrite.relativePath, count: rewrite.count))
        }

        return Outcome(linksRewritten: rewrites)
    }
}
