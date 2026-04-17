import Foundation

struct GetHeadingsArgs: Codable {
    let relativePath: String
    let vault: String?
}

struct GetHeadingsResult: Codable {
    struct HeadingEntry: Codable {
        let text: String
        let level: Int
        let lineNumber: Int
    }
    let vault: String
    let relativePath: String
    let headings: [HeadingEntry]
}

func getHeadings(_ args: GetHeadingsArgs, vaults: [LoadedVault]) async throws -> GetHeadingsResult {
    guard !args.relativePath.isEmpty else {
        throw ToolError.missingArgument("relative_path")
    }

    switch VaultResolver.resolve(relativePath: args.relativePath, hint: args.vault, in: vaults) {
    case .notFound:
        throw ToolError.noteNotFound(args.relativePath)
    case .ambiguous(let matches):
        throw ToolError.ambiguousVault(
            relativePath: args.relativePath,
            matches: matches.map { $0.url.lastPathComponent }
        )
    case .resolved(let loaded):
        guard let indexed = loaded.index.file(forRelativePath: args.relativePath) else {
            throw ToolError.noteNotFound(args.relativePath)
        }
        let headings = loaded.index.headings(forFileId: indexed.id).map {
            GetHeadingsResult.HeadingEntry(text: $0.text, level: $0.level, lineNumber: $0.lineNumber)
        }
        return GetHeadingsResult(
            vault: loaded.url.lastPathComponent,
            relativePath: args.relativePath,
            headings: headings
        )
    }
}
