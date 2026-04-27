import Foundation

/// Applies a `WikiOperation` to a vault root atomically. "Atomic" here means:
/// every precondition is checked up front (no file is written if any check
/// fails); any mid-apply failure rolls back changes that already landed.
/// Platform-agnostic — iOS can reuse this once diff review lands there.
public enum WikiOperationApplier {

    public enum ApplyError: Error, Equatable, Sendable {
        case pathAlreadyExists(String)
        case pathNotFound(String)
        case modifyBaseMismatch(String)
        case deleteContentMismatch(String)
        case nonUTF8Contents(String)
        case ioFailure(path: String, message: String)
        /// The primary apply failed and the subsequent rollback also hit errors.
        /// `applied` lists the paths whose disk state may be inconsistent with
        /// both the pre-apply and post-apply world — surface this to the user.
        case rollbackFailed(original: String, applied: [String])
    }

    /// Applies `operation` under `vaultRoot`. Throws on validation failure,
    /// precondition failure, or mid-apply IO failure. On mid-apply failure,
    /// attempts rollback and throws with either the original cause or
    /// `.rollbackFailed` if rollback itself hit errors.
    public static func apply(
        _ operation: WikiOperation,
        at vaultRoot: URL,
        fileManager: FileManager = .default
    ) throws {
        try operation.validate()

        let originalStates = try precheck(operation, at: vaultRoot, fileManager: fileManager)

        var appliedUndos: [(path: String, undo: () throws -> Void)] = []

        do {
            for change in operation.changes {
                let target = try targetURL(for: change.path, vaultRoot: vaultRoot, fileManager: fileManager)
                switch change {
                case .create(_, let contents):
                    let createdDirectories = try ensureParentDirectoryExists(for: target, fileManager: fileManager)
                    appliedUndos.append((change.path, {
                        if fileManager.fileExists(atPath: target.path) {
                            try CoordinatedFileIO.delete(at: target)
                        }
                        try removeCreatedDirectories(createdDirectories, fileManager: fileManager)
                    }))
                    try writeUTF8(contents, to: target)

                case .modify(_, _, let after):
                    guard case .file(let exactBefore)? = originalStates[change.path] else {
                        throw ApplyError.pathNotFound(change.path)
                    }
                    try writeUTF8(after, to: target)
                    appliedUndos.append((change.path, {
                        try writeUTF8(exactBefore, to: target)
                    }))

                case .delete:
                    guard case .file(let exactContents)? = originalStates[change.path] else {
                        throw ApplyError.pathNotFound(change.path)
                    }
                    try CoordinatedFileIO.delete(at: target)
                    appliedUndos.append((change.path, {
                        _ = try ensureParentDirectoryExists(for: target, fileManager: fileManager)
                        try writeUTF8(exactContents, to: target)
                    }))
                }
            }
        } catch {
            let failingDescription = String(describing: error)
            var rollbackFailures: [String] = []
            for entry in appliedUndos.reversed() {
                do { try entry.undo() }
                catch { rollbackFailures.append(entry.path) }
            }
            if rollbackFailures.isEmpty {
                throw error
            } else {
                throw ApplyError.rollbackFailed(original: failingDescription, applied: rollbackFailures)
            }
        }
    }

    // MARK: - Precheck

    private enum OriginalState {
        case absent
        case file(String)
    }

    private static func precheck(
        _ operation: WikiOperation,
        at vaultRoot: URL,
        fileManager: FileManager
    ) throws -> [String: OriginalState] {
        var originals: [String: OriginalState] = [:]
        for change in operation.changes {
            let target = try targetURL(for: change.path, vaultRoot: vaultRoot, fileManager: fileManager)
            switch change {
            case .create:
                if fileManager.fileExists(atPath: target.path) {
                    throw ApplyError.pathAlreadyExists(change.path)
                }
                originals[change.path] = .absent
            case .modify(_, let before, _):
                guard fileManager.fileExists(atPath: target.path) else {
                    throw ApplyError.pathNotFound(change.path)
                }
                let current = try readUTF8(at: target, changePath: change.path)
                if !looseEqual(current, before) {
                    throw ApplyError.modifyBaseMismatch(change.path)
                }
                originals[change.path] = .file(current)
            case .delete(_, let contents):
                guard fileManager.fileExists(atPath: target.path) else {
                    throw ApplyError.pathNotFound(change.path)
                }
                let current = try readUTF8(at: target, changePath: change.path)
                if !looseEqual(current, contents) {
                    throw ApplyError.deleteContentMismatch(change.path)
                }
                originals[change.path] = .file(current)
            }
        }
        return originals
    }

    // MARK: - Tolerant comparison

    /// LLMs frequently drop the final trailing newline or trim line-end
    /// whitespace when they echo a file's contents into a JSON string.
    /// Reject those trivial differences as "same enough" — they don't
    /// represent any real user edit we could lose.
    static func looseEqual(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        return normalize(a) == normalize(b)
    }

    private static func normalize(_ s: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                // Trim trailing whitespace on each line — most common LLM
                // drift. Keep leading whitespace (indentation is meaningful).
                var end = line.endIndex
                while end > line.startIndex {
                    let prev = line.index(before: end)
                    if line[prev].isWhitespace { end = prev } else { break }
                }
                return String(line[line.startIndex..<end])
            }
            .joined(separator: "\n")
            .trimmingTrailingNewlines()
    }

    // MARK: - File helpers

    private static func targetURL(for path: String, vaultRoot: URL, fileManager: FileManager) throws -> URL {
        let rawRoot = vaultRoot.standardizedFileURL
        let resolvedRoot = rawRoot.resolvingSymlinksInPath()
        var rawCursor = rawRoot
        var resolvedCursor = resolvedRoot

        for component in path.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            rawCursor = rawCursor.appendingPathComponent(component).standardizedFileURL

            var checkedURL = resolvedCursor.appendingPathComponent(component).standardizedFileURL
            if fileManager.fileExists(atPath: rawCursor.path) {
                checkedURL = rawCursor.resolvingSymlinksInPath().standardizedFileURL
            }

            guard isInsideVault(checkedURL, root: resolvedRoot) else {
                throw WikiOperationError.pathEscapesVault(path)
            }
            resolvedCursor = checkedURL
        }

        return rawCursor
    }

    private static func isInsideVault(_ url: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        if rootPath == "/" { return targetPath.hasPrefix("/") }
        return targetPath == rootPath || targetPath.hasPrefix(rootPath + "/")
    }

    private static func ensureParentDirectoryExists(for url: URL, fileManager: FileManager) throws -> [URL] {
        let parent = url.deletingLastPathComponent()
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: parent.path, isDirectory: &isDir) {
            return []
        }

        var missing: [URL] = []
        var cursor = parent
        while !fileManager.fileExists(atPath: cursor.path, isDirectory: &isDir) {
            missing.append(cursor)
            let next = cursor.deletingLastPathComponent()
            if next.path == cursor.path { break }
            cursor = next
        }

        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        return missing
    }

    private static func removeCreatedDirectories(_ directories: [URL], fileManager: FileManager) throws {
        for directory in directories {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDir),
                  isDir.boolValue else {
                continue
            }
            let contents = try fileManager.contentsOfDirectory(atPath: directory.path)
            if contents.isEmpty {
                try CoordinatedFileIO.delete(at: directory)
            }
        }
    }

    private static func writeUTF8(_ text: String, to url: URL) throws {
        guard let data = text.data(using: .utf8) else {
            throw ApplyError.nonUTF8Contents(url.path)
        }
        try CoordinatedFileIO.write(data, to: url)
    }

    private static func readUTF8(at url: URL, changePath: String) throws -> String {
        let data: Data
        do { data = try CoordinatedFileIO.read(at: url) }
        catch { throw ApplyError.ioFailure(path: changePath, message: String(describing: error)) }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ApplyError.nonUTF8Contents(changePath)
        }
        return text
    }
}

private extension String {
    func trimmingTrailingNewlines() -> String {
        var result = self
        while result.last == "\n" || result.last == "\r" {
            result.removeLast()
        }
        return result
    }
}
