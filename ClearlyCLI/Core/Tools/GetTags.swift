import Foundation

struct GetTagsArgs: Codable {
    let tag: String?
}

struct GetTagsResult: Codable {
    enum Mode: String, Codable {
        case all
        case byTag = "by_tag"
    }
    struct TagSummary: Codable {
        let tag: String
        let count: Int
    }
    struct TagFile: Codable {
        let vault: String
        let vaultPath: String
        let relativePath: String
    }
    let mode: Mode
    let tag: String?
    let allTags: [TagSummary]?
    let files: [TagFile]?
}

func getTags(_ args: GetTagsArgs, vaults: [LoadedVault]) async throws -> GetTagsResult {
    if let tag = args.tag, !tag.isEmpty {
        var files: [GetTagsResult.TagFile] = []
        for vault in vaults {
            let vaultName = vault.url.lastPathComponent
            let vaultPath = vault.url.path
            for f in vault.index.filesForTag(tag: tag) {
                files.append(
                    GetTagsResult.TagFile(
                        vault: vaultName,
                        vaultPath: vaultPath,
                        relativePath: f.path
                    )
                )
            }
        }
        return GetTagsResult(mode: .byTag, tag: tag, allTags: nil, files: files)
    } else {
        var counts: [String: Int] = [:]
        for vault in vaults {
            for (t, c) in vault.index.allTags() {
                counts[t, default: 0] += c
            }
        }
        let sorted = counts.sorted { $0.key < $1.key }
        return GetTagsResult(
            mode: .all,
            tag: nil,
            allTags: sorted.map { GetTagsResult.TagSummary(tag: $0.key, count: $0.value) },
            files: nil
        )
    }
}
