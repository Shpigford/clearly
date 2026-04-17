import Foundation

enum PathGuard {
    /// Resolve a vault-relative path to an absolute URL inside the vault.
    ///
    /// Rejects paths that are absolute, contain `..` segments, contain null
    /// bytes, or resolve (after symlink resolution) outside the vault root.
    /// Phase 2 implements the baseline safety net; Phase 3 extends the matrix
    /// (APFS case canonicalization, unicode lookalikes, symlink-to-/, etc.).
    ///
    /// Throws `ToolError` directly so callers in CLI and MCP share a single
    /// error surface — no intermediate error type.
    static func resolve(relativePath: String, in vaultURL: URL) throws -> URL {
        if relativePath.isEmpty {
            throw ToolError.invalidArgument(name: "relative_path", reason: "must not be empty")
        }
        if relativePath.contains("\0") {
            throw ToolError.invalidArgument(name: "relative_path", reason: "must not contain null bytes")
        }
        if relativePath.hasPrefix("/") {
            throw ToolError.pathOutsideVault(relativePath)
        }

        // Unicode traversal lookalikes
        if relativePath.contains("\u{2025}") ||
           relativePath.contains("\u{FF0E}\u{FF0E}") {
            throw ToolError.pathOutsideVault(relativePath)
        }

        // Windows-style traversal
        if relativePath.contains("..\\") {
            throw ToolError.pathOutsideVault(relativePath)
        }

        // Shell metacharacters
        if relativePath.contains("$(") || relativePath.contains("`") {
            throw ToolError.invalidArgument(name: "relative_path", reason: "must not contain shell metacharacters")
        }

        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        for component in components {
            if component == ".." || component == "\u{2025}" {
                throw ToolError.pathOutsideVault(relativePath)
            }
        }

        let vaultRoot = vaultURL.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = vaultRoot.appendingPathComponent(relativePath)
        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()

        let rootComponents = vaultRoot.pathComponents
        let resolvedComponents = resolved.pathComponents
        guard resolvedComponents.count >= rootComponents.count,
              Array(resolvedComponents.prefix(rootComponents.count)) == rootComponents
        else {
            throw ToolError.pathOutsideVault(relativePath)
        }

        return resolved
    }
}
