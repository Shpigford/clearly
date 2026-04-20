import Foundation
import ClearlyCore

enum VaultResolver {
    enum Resolution {
        case resolved(LoadedVault)
        case notFound
        case ambiguous([LoadedVault])
    }

    /// Resolve which loaded vault owns a vault-relative path.
    ///
    /// Semantics:
    /// - `hint` matches a vault by its basename (`lastPathComponent`) or by its
    ///   full standardized path.
    /// - For each candidate vault, `PathGuard.resolve` runs — this throws
    ///   `ToolError.pathOutsideVault` / `.invalidArgument` for unsafe paths
    ///   (absolute, `..`, null bytes, symlink escape) *before* any file-system
    ///   existence check. Callers get a consistent error identifier.
    /// - Exactly one hit on disk → `.resolved`. Zero → `.notFound`. >1 → `.ambiguous`.
    static func resolve(relativePath: String, hint: String?, in vaults: [LoadedVault]) throws -> Resolution {
        let filtered: [LoadedVault]
        if let hint = hint, !hint.isEmpty {
            let hintPath = URL(fileURLWithPath: hint).standardizedFileURL.path
            filtered = vaults.filter { vault in
                vault.url.lastPathComponent == hint ||
                vault.url.standardizedFileURL.path == hintPath
            }
            if filtered.isEmpty {
                return .notFound
            }
        } else {
            filtered = vaults
        }

        var hits: [LoadedVault] = []
        for vault in filtered {
            let resolvedURL = try PathGuard.resolve(relativePath: relativePath, in: vault.url)
            if FileManager.default.fileExists(atPath: resolvedURL.path) {
                hits.append(vault)
            }
        }
        switch hits.count {
        case 0: return .notFound
        case 1: return .resolved(hits[0])
        default: return .ambiguous(hits)
        }
    }

    static func resolveForWrite(relativePath: String, hint: String?, in vaults: [LoadedVault]) throws -> Resolution {
        let filtered: [LoadedVault]
        if let hint = hint, !hint.isEmpty {
            let hintPath = URL(fileURLWithPath: hint).standardizedFileURL.path
            filtered = vaults.filter { vault in
                vault.url.lastPathComponent == hint ||
                vault.url.standardizedFileURL.path == hintPath
            }
            if filtered.isEmpty { return .notFound }
        } else {
            filtered = vaults
        }

        guard filtered.count == 1 else {
            return .ambiguous(filtered)
        }

        let _ = try PathGuard.resolve(relativePath: relativePath, in: filtered[0].url)
        return .resolved(filtered[0])
    }

}
