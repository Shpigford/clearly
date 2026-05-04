import Foundation

/// Classification of a vault folder. The `wiki` case is retained so older
/// `BookmarkedLocation` JSON (saved before LLM Wiki was removed) still
/// decodes — its presence is now meaningless and treated identically to
/// `.regular` everywhere in the app.
public enum VaultKind: String, Codable, Equatable, Sendable {
    case regular
    case wiki
}

extension VaultKind {
    /// Inspect a vault root and return its kind. Always returns `.regular`
    /// now; LLM Wiki marker detection (`AGENTS.md` + `index.md` + `log.md`)
    /// has been removed, so legacy wikis open as ordinary vaults.
    public static func detect(at vaultRoot: URL, fileManager: FileManager = .default) -> VaultKind {
        _ = vaultRoot
        _ = fileManager
        return .regular
    }
}
