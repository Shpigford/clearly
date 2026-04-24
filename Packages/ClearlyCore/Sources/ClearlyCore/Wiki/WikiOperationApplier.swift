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

        try precheck(operation, at: vaultRoot, fileManager: fileManager)

        var appliedUndos: [(path: String, undo: () throws -> Void)] = []

        do {
            for change in operation.changes {
                let target = vaultRoot.appendingPathComponent(change.path)
                switch change {
                case .create(_, let contents):
                    try ensureParentDirectoryExists(for: target, fileManager: fileManager)
                    try writeUTF8(contents, to: target)
                    appliedUndos.append((change.path, {
                        try CoordinatedFileIO.delete(at: target)
                    }))

                case .modify(_, let before, let after):
                    try writeUTF8(after, to: target)
                    appliedUndos.append((change.path, {
                        try writeUTF8(before, to: target)
                    }))

                case .delete(_, let contents):
                    try CoordinatedFileIO.delete(at: target)
                    appliedUndos.append((change.path, {
                        try ensureParentDirectoryExists(for: target, fileManager: fileManager)
                        try writeUTF8(contents, to: target)
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

    private static func precheck(
        _ operation: WikiOperation,
        at vaultRoot: URL,
        fileManager: FileManager
    ) throws {
        for change in operation.changes {
            let target = vaultRoot.appendingPathComponent(change.path)
            switch change {
            case .create:
                if fileManager.fileExists(atPath: target.path) {
                    throw ApplyError.pathAlreadyExists(change.path)
                }
            case .modify(_, let before, _):
                guard fileManager.fileExists(atPath: target.path) else {
                    throw ApplyError.pathNotFound(change.path)
                }
                let current = try readUTF8(at: target, changePath: change.path)
                if current != before {
                    throw ApplyError.modifyBaseMismatch(change.path)
                }
            case .delete(_, let contents):
                guard fileManager.fileExists(atPath: target.path) else {
                    throw ApplyError.pathNotFound(change.path)
                }
                let current = try readUTF8(at: target, changePath: change.path)
                if current != contents {
                    throw ApplyError.deleteContentMismatch(change.path)
                }
            }
        }
    }

    // MARK: - File helpers

    private static func ensureParentDirectoryExists(for url: URL, fileManager: FileManager) throws {
        let parent = url.deletingLastPathComponent()
        var isDir: ObjCBool = false
        if !fileManager.fileExists(atPath: parent.path, isDirectory: &isDir) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
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
