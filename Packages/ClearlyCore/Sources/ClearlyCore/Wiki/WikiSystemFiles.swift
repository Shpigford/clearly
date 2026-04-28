import Foundation

/// Vault-relative paths the wiki treats as infrastructure rather than user
/// content. Centralized so the integrate pass, the inventory listing, and any
/// future scanner agree on the same skip rules. Add new entries here, not in
/// callsites.
public enum WikiSystemFiles {

    /// Top-level filenames that aren't user notes — the wiki's own scaffolding.
    /// Anchored to vault root: a `Notes/index.md` is user content and won't
    /// match.
    public static let reservedRootFiles: Set<String> = [
        "index.md",
        "log.md",
        "AGENTS.md",
        "getting-started.md",
    ]

    /// Top-level folders the agent is asked not to crawl. `raw/` is the
    /// immutable source-material area; `_audit/` is where Review parks its
    /// own artefacts. Path matching is segment-anchored, so `raw_data.md`
    /// at the root is NOT excluded.
    public static let reservedRootFolders: Set<String> = [
        "raw",
        "_audit",
    ]

    /// `true` if the vault-relative path is wiki infrastructure that
    /// integration / inventory passes should skip. Caller must pass forward-
    /// slash, vault-relative paths with no leading `/`. Empty paths return
    /// `true` (degenerate input — skip).
    public static func isExcluded(vaultRelativePath: String) -> Bool {
        if vaultRelativePath.isEmpty { return true }
        let segments = vaultRelativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let first = segments.first, !first.isEmpty else { return true }

        // Hidden segment anywhere in the path → skip. Catches `.clearly/state.json`,
        // dotfiles at root, and dot-prefixed subfolders.
        if segments.contains(where: { $0.hasPrefix(".") }) { return true }

        if segments.count == 1, reservedRootFiles.contains(first) { return true }
        if reservedRootFolders.contains(first) { return true }
        return false
    }
}
