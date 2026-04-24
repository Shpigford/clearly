import Foundation

/// Classification of a vault folder. Regular vaults behave like Clearly today;
/// wiki vaults gain LLM-authored-knowledge-base chrome (log sidebar, lint
/// dashboard, Ingest/Query/Lint commands).
///
/// Detection is marker-based: a vault is a wiki if its root contains all three
/// of `AGENTS.md`, `index.md`, and `log.md`. The triple is a deliberate
/// convention — any single file could exist in a regular vault by coincidence.
public enum VaultKind: Equatable, Sendable {
    case regular
    case wiki

    public var isWiki: Bool {
        if case .wiki = self { return true }
        return false
    }
}

public enum WikiMarker: String, CaseIterable, Sendable {
    case agents = "AGENTS.md"
    case index = "index.md"
    case log = "log.md"
}

extension VaultKind {
    /// Inspect a vault root and return its kind.
    ///
    /// Runs three `fileExists` checks against the vault root. Safe to call from
    /// a background queue (and must, per `CLAUDE.md`'s threading rule for
    /// filesystem I/O). Does not recurse.
    public static func detect(at vaultRoot: URL, fileManager: FileManager = .default) -> VaultKind {
        for marker in WikiMarker.allCases {
            let url = vaultRoot.appendingPathComponent(marker.rawValue)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                return .regular
            }
        }
        return .wiki
    }
}
