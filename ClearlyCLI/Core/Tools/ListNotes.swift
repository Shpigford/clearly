import Foundation
import ClearlyCore

struct ListNotesArgs: Codable {
    let under: String?
    let vault: String?
}

struct ListNotesResult: Codable {
    struct NoteSummary: Codable {
        let vault: String
        let relativePath: String
        let filename: String
        let modifiedAt: String
        let sizeBytes: Int
    }
    let notes: [NoteSummary]
}

func listNotes(_ args: ListNotesArgs, vaults: [LoadedVault]) async throws -> ListNotesResult {
    let targetVaults: [LoadedVault]
    if let hint = args.vault, !hint.isEmpty {
        let hintPath = URL(fileURLWithPath: hint).standardizedFileURL.path
        targetVaults = vaults.filter { vault in
            vault.url.lastPathComponent == hint ||
            vault.url.standardizedFileURL.path == hintPath
        }
        if targetVaults.isEmpty {
            throw ToolError.invalidArgument(
                name: "vault",
                reason: "no loaded vault named or located at '\(hint)'"
            )
        }
    } else {
        targetVaults = vaults
    }

    let underPrefix: String?
    if let raw = args.under, !raw.isEmpty {
        underPrefix = raw.hasSuffix("/") ? raw : raw + "/"
    } else {
        underPrefix = nil
    }

    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    var notes: [ListNotesResult.NoteSummary] = []
    for loaded in targetVaults {
        let tree = FileNode.buildTree(at: loaded.url, showHiddenFiles: false, ignoreRules: nil)
        collectFiles(tree, vaultURL: loaded.url, vaultName: loaded.url.lastPathComponent, iso: iso, under: underPrefix, into: &notes)
    }
    return ListNotesResult(notes: notes)
}

private func collectFiles(
    _ nodes: [FileNode],
    vaultURL: URL,
    vaultName: String,
    iso: ISO8601DateFormatter,
    under: String?,
    into notes: inout [ListNotesResult.NoteSummary]
) {
    for node in nodes {
        if let children = node.children {
            collectFiles(children, vaultURL: vaultURL, vaultName: vaultName, iso: iso, under: under, into: &notes)
            continue
        }
        let relativePath = relativePath(of: node.url, from: vaultURL)
        if let under, !relativePath.hasPrefix(under) {
            continue
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: node.url.path)
        let modified = (attrs?[.modificationDate] as? Date) ?? Date()
        let size = (attrs?[.size] as? Int) ?? 0

        notes.append(ListNotesResult.NoteSummary(
            vault: vaultName,
            relativePath: relativePath,
            filename: node.name,
            modifiedAt: iso.string(from: modified),
            sizeBytes: size
        ))
    }
}

private func relativePath(of fileURL: URL, from vaultURL: URL) -> String {
    let root = vaultURL.standardizedFileURL.path
    let full = fileURL.standardizedFileURL.path
    if full.hasPrefix(root + "/") {
        return String(full.dropFirst(root.count + 1))
    }
    return full
}
