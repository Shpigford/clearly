import Foundation

struct GetTagsArgs: Codable {
    let tag: String?
}

struct GetTagsResult: Codable {
    struct TagEntry: Codable {
        let tag: String
        let count: Int
    }
    struct FileEntry: Codable {
        let vaultPath: String
        let path: String
    }
    enum Mode: String, Codable {
        case all
        case byTag
    }
    let mode: Mode
    let tag: String?
    let allTags: [TagEntry]?
    let files: [FileEntry]?
}

func getTags(_ args: GetTagsArgs, vaults: [LoadedVault]) async throws -> GetTagsResult {
    if let tag = args.tag, !tag.isEmpty {
        var files: [GetTagsResult.FileEntry] = []
        for vault in vaults {
            for f in vault.index.filesForTag(tag: tag) {
                files.append(GetTagsResult.FileEntry(vaultPath: vault.url.path, path: f.path))
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
            allTags: sorted.map { GetTagsResult.TagEntry(tag: $0.key, count: $0.value) },
            files: nil
        )
    }
}
