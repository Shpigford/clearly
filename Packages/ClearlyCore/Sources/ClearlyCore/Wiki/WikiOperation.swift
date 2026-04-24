import Foundation

/// A proposed change to a Wiki vault, produced by an agent recipe (Ingest /
/// Query / Lint) or by the `propose_operation` MCP tool. A `WikiOperation` is
/// staged — the user reviews it in a full-screen diff sheet and accepts or
/// rejects the whole operation. Writes never land on disk until the user
/// accepts.
///
/// Pure data, platform-agnostic, Codable for the MCP wire format and for
/// replaying historical operations from `log.md`. Actual apply/rollback lives
/// in the Mac-side `WikiOperationController` (Phase B2).
public struct WikiOperation: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let kind: OperationKind
    public let title: String
    public let rationale: String
    public let changes: [FileChange]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: OperationKind,
        title: String,
        rationale: String,
        changes: [FileChange],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.rationale = rationale
        self.changes = changes
        self.createdAt = createdAt
    }
}

public enum OperationKind: String, Codable, Sendable, CaseIterable {
    case ingest
    case query
    case lint
    case other
}

/// A single file-level change inside a `WikiOperation`. `path` is always
/// vault-relative, uses forward slashes, and contains no `..` segments — the
/// controller resolves it against the active vault root when applying.
public enum FileChange: Sendable, Equatable, Identifiable {
    case create(path: String, contents: String)
    case modify(path: String, before: String, after: String)
    case delete(path: String, contents: String)

    public var id: String {
        switch self {
        case .create(let path, _), .modify(let path, _, _), .delete(let path, _):
            return path
        }
    }

    public var path: String { id }
}

// MARK: - FileChange Codable

/// Wire format:
///   create: { "type": "create", "path": "foo.md", "contents": "..." }
///   modify: { "type": "modify", "path": "foo.md", "before": "...", "after": "..." }
///   delete: { "type": "delete", "path": "foo.md", "contents": "..." }
extension FileChange: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, path, contents, before, after
    }

    private enum Kind: String, Codable {
        case create, modify, delete
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .type)
        let path = try c.decode(String.self, forKey: .path)
        switch kind {
        case .create:
            self = .create(path: path, contents: try c.decode(String.self, forKey: .contents))
        case .modify:
            self = .modify(
                path: path,
                before: try c.decode(String.self, forKey: .before),
                after: try c.decode(String.self, forKey: .after)
            )
        case .delete:
            self = .delete(path: path, contents: try c.decode(String.self, forKey: .contents))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .create(let path, let contents):
            try c.encode(Kind.create, forKey: .type)
            try c.encode(path, forKey: .path)
            try c.encode(contents, forKey: .contents)
        case .modify(let path, let before, let after):
            try c.encode(Kind.modify, forKey: .type)
            try c.encode(path, forKey: .path)
            try c.encode(before, forKey: .before)
            try c.encode(after, forKey: .after)
        case .delete(let path, let contents):
            try c.encode(Kind.delete, forKey: .type)
            try c.encode(path, forKey: .path)
            try c.encode(contents, forKey: .contents)
        }
    }
}

// MARK: - Validation

public enum WikiOperationError: Error, Equatable, Sendable {
    case noChanges
    case duplicatePath(String)
    case pathIsAbsolute(String)
    case pathEscapesVault(String)
    case pathIsEmpty
    case noOpModify(String)
}

extension WikiOperation {
    /// Throws if the operation is structurally invalid. Run this at the
    /// boundary where an operation enters the system — decoding from an agent
    /// response, hand-construction in tests — before the user sees a diff for
    /// something that can't be applied.
    public func validate() throws {
        if changes.isEmpty { throw WikiOperationError.noChanges }
        var seen = Set<String>()
        for change in changes {
            try FileChange.validatePath(change.path)
            if !seen.insert(change.path).inserted {
                throw WikiOperationError.duplicatePath(change.path)
            }
            if case .modify(_, let before, let after) = change, before == after {
                throw WikiOperationError.noOpModify(change.path)
            }
        }
    }
}

extension FileChange {
    static func validatePath(_ path: String) throws {
        if path.isEmpty { throw WikiOperationError.pathIsEmpty }
        if path.hasPrefix("/") { throw WikiOperationError.pathIsAbsolute(path) }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        if components.contains("..") { throw WikiOperationError.pathEscapesVault(path) }
    }
}
