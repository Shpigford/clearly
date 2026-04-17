import Foundation

struct LoadedVault {
    let index: VaultIndex
    let url: URL
}

enum IndexSetError: Error {
    case noVaults
    case noIndexes
    case pathsMissing([String])
}

enum IndexSet {
    static func openIndexes(_ opts: GlobalOptions) throws -> [LoadedVault] {
        let candidatePaths: [String]
        if !opts.vault.isEmpty {
            candidatePaths = opts.vault
        } else {
            candidatePaths = VaultDiscovery.discover(bundleID: opts.bundleID)
        }

        guard !candidatePaths.isEmpty else {
            throw IndexSetError.noVaults
        }

        let existing = candidatePaths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else {
            throw IndexSetError.pathsMissing(candidatePaths)
        }

        var loaded: [LoadedVault] = []
        for path in existing {
            let url = URL(fileURLWithPath: path)
            do {
                let index = try VaultIndex(locationURL: url, bundleIdentifier: opts.bundleID)
                loaded.append(LoadedVault(index: index, url: url))
            } catch {
                FileHandle.standardError.write(
                    Data("Warning: Cannot open index for \(path): \(error)\n".utf8)
                )
            }
        }

        guard !loaded.isEmpty else {
            throw IndexSetError.noIndexes
        }
        return loaded
    }
}
