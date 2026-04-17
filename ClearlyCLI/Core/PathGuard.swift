import Foundation

enum PathGuardError: Error, LocalizedError {
    case pathOutsideVault(String)
    case invalidPath(String)

    var errorDescription: String? {
        switch self {
        case .pathOutsideVault(let path):
            return "Path resolves outside the vault: \(path)"
        case .invalidPath(let reason):
            return "Invalid path: \(reason)"
        }
    }
}

enum PathGuard {
    /// Resolve a vault-relative path to an absolute URL inside the vault.
    ///
    /// Rejects paths that are absolute, contain `..` segments, contain null bytes,
    /// or resolve (after symlink resolution) outside the vault root.
    /// Phase 2 implements the baseline safety net; Phase 3 extends the matrix
    /// (APFS case canonicalization, unicode lookalikes, symlink-to-/, etc.).
    static func resolve(relativePath: String, in vaultURL: URL) throws -> URL {
        if relativePath.isEmpty {
            throw PathGuardError.invalidPath("empty path")
        }
        if relativePath.contains("\0") {
            throw PathGuardError.invalidPath("null byte in path")
        }
        if relativePath.hasPrefix("/") {
            throw PathGuardError.invalidPath("absolute paths are not allowed: \(relativePath)")
        }

        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        for component in components {
            if component == ".." {
                throw PathGuardError.invalidPath("parent traversal (..) is not allowed: \(relativePath)")
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
            throw PathGuardError.pathOutsideVault(relativePath)
        }

        return resolved
    }
}
