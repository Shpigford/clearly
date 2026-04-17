import Foundation

enum VaultResolver {
    enum Resolution {
        case resolved(LoadedVault)
        case notFound
        case ambiguous([LoadedVault])
    }

    /// Resolve which loaded vault owns a vault-relative path.
    ///
    /// Semantics:
    /// - `hint` matches a vault by its basename (`lastPathComponent`) or by its full standardized path.
    /// - Among vaults matching the hint (or all vaults if no hint), the file at `<vault>/<relativePath>` is checked.
    /// - Exactly one hit → `.resolved`. Zero hits → `.notFound`. More than one → `.ambiguous`.
    static func resolve(relativePath: String, hint: String?, in vaults: [LoadedVault]) -> Resolution {
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

        let hits = filtered.filter { vault in
            let target = vault.url.appendingPathComponent(relativePath).path
            return FileManager.default.fileExists(atPath: target)
        }
        switch hits.count {
        case 0: return .notFound
        case 1: return .resolved(hits[0])
        default: return .ambiguous(hits)
        }
    }
}
