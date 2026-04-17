import Foundation

enum VaultResolver {
    enum Resolution {
        case resolved(LoadedVault)
        case notFound
        case ambiguous([LoadedVault])
    }

    static func resolve(path: String, in vaults: [LoadedVault]) -> Resolution {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        let matches = vaults.filter { vault in
            let root = vault.url.standardizedFileURL.path
            return root == normalized || normalized.hasPrefix(root + "/")
        }
        switch matches.count {
        case 0: return .notFound
        case 1: return .resolved(matches[0])
        default: return .ambiguous(matches)
        }
    }
}
