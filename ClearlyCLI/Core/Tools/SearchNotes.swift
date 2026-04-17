import Foundation

struct SearchNotesArgs: Codable {
    let query: String
    let limit: Int?
}

struct SearchNotesResult: Codable {
    struct Excerpt: Codable {
        let lineNumber: Int
        let contextLine: String
    }
    struct Match: Codable {
        let vaultPath: String
        let path: String
        let matchesFilename: Bool
        let excerpts: [Excerpt]
    }
    let query: String
    let totalCount: Int
    let returnedCount: Int
    let results: [Match]
}

func searchNotes(_ args: SearchNotesArgs, vaults: [LoadedVault]) async throws -> SearchNotesResult {
    guard !args.query.isEmpty else {
        throw ToolError.missingArgument("query")
    }
    if let rawLimit = args.limit, rawLimit <= 0 {
        throw ToolError.invalidArgument(name: "limit", reason: "must be greater than 0")
    }
    let limit = min(args.limit ?? 20, 100)

    var all: [(vaultPath: String, group: SearchFileGroup)] = []
    for vault in vaults {
        for group in vault.index.searchFilesGrouped(query: args.query) {
            all.append((vault.url.path, group))
        }
    }
    all.sort(by: isHigherPrioritySearchResult)

    let capped = Array(all.prefix(limit))
    let matches = capped.map { item in
        SearchNotesResult.Match(
            vaultPath: item.vaultPath,
            path: item.group.file.path,
            matchesFilename: item.group.matchesFilename,
            excerpts: item.group.excerpts.map {
                SearchNotesResult.Excerpt(lineNumber: $0.lineNumber, contextLine: $0.contextLine)
            }
        )
    }
    return SearchNotesResult(
        query: args.query,
        totalCount: all.count,
        returnedCount: capped.count,
        results: matches
    )
}

private func isHigherPrioritySearchResult(
    _ lhs: (vaultPath: String, group: SearchFileGroup),
    _ rhs: (vaultPath: String, group: SearchFileGroup)
) -> Bool {
    if lhs.group.matchesFilename != rhs.group.matchesFilename {
        return lhs.group.matchesFilename
    }
    if lhs.group.relevanceRank != rhs.group.relevanceRank {
        return lhs.group.relevanceRank < rhs.group.relevanceRank
    }
    if lhs.vaultPath != rhs.vaultPath {
        return lhs.vaultPath.localizedCaseInsensitiveCompare(rhs.vaultPath) == .orderedAscending
    }
    return lhs.group.file.path.localizedCaseInsensitiveCompare(rhs.group.file.path) == .orderedAscending
}
