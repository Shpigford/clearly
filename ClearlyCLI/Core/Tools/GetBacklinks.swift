import Foundation

struct GetBacklinksArgs: Codable {
    let relativePath: String
    let vault: String?
}

struct GetBacklinksResult: Codable {
    struct Linked: Codable {
        let vault: String
        let relativePath: String
        let lineNumber: Int?
        let displayText: String?
        let context: String?
    }
    struct Unlinked: Codable {
        let vault: String
        let relativePath: String
        let lineNumber: Int
        let contextLine: String
    }
    let vault: String
    let relativePath: String
    let linked: [Linked]
    let unlinked: [Unlinked]
}

func getBacklinks(_ args: GetBacklinksArgs, vaults: [LoadedVault]) async throws -> GetBacklinksResult {
    guard !args.relativePath.isEmpty else {
        throw ToolError.missingArgument("relative_path")
    }

    // Honor optional `vault` hint to scope lookup in a multi-vault setup.
    let searchSpace: [LoadedVault]
    if let hint = args.vault, !hint.isEmpty {
        searchSpace = vaults.filter {
            $0.url.lastPathComponent == hint || $0.url.path == hint
        }
        if searchSpace.isEmpty {
            throw ToolError.noteNotFound(args.relativePath)
        }
    } else {
        searchSpace = vaults
    }

    for loaded in searchSpace {
        let file: IndexedFile?
        if let f = loaded.index.file(forRelativePath: args.relativePath) {
            file = f
        } else if let f = loaded.index.resolveWikiLink(name: args.relativePath) {
            file = f
        } else {
            let withoutExt = args.relativePath.hasSuffix(".md")
                ? String(args.relativePath.dropLast(3))
                : args.relativePath
            file = loaded.index.resolveWikiLink(name: withoutExt)
        }

        guard let file = file else { continue }
        let vaultName = loaded.url.lastPathComponent

        let linked = loaded.index.linksTo(fileId: file.id).map { link in
            GetBacklinksResult.Linked(
                vault: vaultName,
                relativePath: link.sourcePath ?? link.sourceFilename ?? "unknown",
                lineNumber: link.lineNumber,
                displayText: link.displayText,
                context: link.context
            )
        }
        let unlinked = loaded.index.unlinkedMentions(
            for: file.filename,
            excludingFileId: file.id
        ).map { mention in
            GetBacklinksResult.Unlinked(
                vault: vaultName,
                relativePath: mention.file.path,
                lineNumber: mention.lineNumber,
                contextLine: mention.contextLine
            )
        }

        return GetBacklinksResult(
            vault: vaultName,
            relativePath: file.path,
            linked: linked,
            unlinked: unlinked
        )
    }

    throw ToolError.noteNotFound(args.relativePath)
}
