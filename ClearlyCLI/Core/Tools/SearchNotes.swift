import Foundation
import ClearlyCore

struct SearchNotesArgs: Codable {
    let query: String
    let limit: Int?
}

struct SearchNotesResult: Codable {
    struct Excerpt: Codable {
        let lineNumber: Int
        let contextLine: String
    }
    struct Hit: Codable {
        let vault: String
        let vaultPath: String
        let relativePath: String
        let filename: String
        let matchesFilename: Bool
        let excerpts: [Excerpt]
    }
    let query: String
    let totalCount: Int
    let returnedCount: Int
    let results: [Hit]
}

func searchNotes(_ args: SearchNotesArgs, vaults: [LoadedVault]) async throws -> SearchNotesResult {
    guard !args.query.isEmpty else {
        throw ToolError.missingArgument("query")
    }
    if let rawLimit = args.limit, rawLimit <= 0 {
        throw ToolError.invalidArgument(name: "limit", reason: "must be greater than 0")
    }
    let limit = min(args.limit ?? 20, 100)

    var all: [(vault: LoadedVault, group: SearchFileGroup)] = []
    for vault in vaults {
        for group in vault.index.searchFilesGrouped(query: args.query) {
            all.append((vault, group))
        }
    }
    all.sort(by: isHigherPrioritySearchResult)

    let capped = Array(all.prefix(limit))
    let hits = capped.map { item in
        SearchNotesResult.Hit(
            vault: item.vault.url.lastPathComponent,
            vaultPath: item.vault.url.path,
            relativePath: item.group.file.path,
            filename: item.group.file.filename,
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
        results: hits
    )
}

private func isHigherPrioritySearchResult(
    _ lhs: (vault: LoadedVault, group: SearchFileGroup),
    _ rhs: (vault: LoadedVault, group: SearchFileGroup)
) -> Bool {
    if lhs.group.matchesFilename != rhs.group.matchesFilename {
        return lhs.group.matchesFilename
    }
    if lhs.group.relevanceRank != rhs.group.relevanceRank {
        return lhs.group.relevanceRank < rhs.group.relevanceRank
    }
    if lhs.vault.url.path != rhs.vault.url.path {
        return lhs.vault.url.path.localizedCaseInsensitiveCompare(rhs.vault.url.path) == .orderedAscending
    }
    return lhs.group.file.path.localizedCaseInsensitiveCompare(rhs.group.file.path) == .orderedAscending
}
