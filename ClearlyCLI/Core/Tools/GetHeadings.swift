import Foundation
import ClearlyCore

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

    switch try VaultResolver.resolve(relativePath: args.relativePath, hint: args.vault, in: vaults) {
    case .notFound:
        throw ToolError.noteNotFound(args.relativePath)
    case .ambiguous(let matches):
        throw ToolError.ambiguousVault(
            relativePath: args.relativePath,
            matches: matches.map { $0.url.lastPathComponent }
        )
    case .resolved(let loaded):
        // File exists on disk (VaultResolver confirmed). If it's not yet in
        // the index, return empty headings rather than note_not_found —
        // matches ReadNote's behavior and avoids a misleading error when the
        // index is just behind.
        let headings: [GetHeadingsResult.HeadingEntry]
        if let indexed = loaded.index.file(forRelativePath: args.relativePath) {
            headings = loaded.index.headings(forFileId: indexed.id).map {
                GetHeadingsResult.HeadingEntry(text: $0.text, level: $0.level, lineNumber: $0.lineNumber)
            }
        } else {
            headings = []
        }
        return GetHeadingsResult(
            vault: loaded.url.lastPathComponent,
            relativePath: args.relativePath,
            headings: headings
        )
    }
}
