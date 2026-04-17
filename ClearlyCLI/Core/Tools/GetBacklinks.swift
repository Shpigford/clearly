import Foundation

struct GetBacklinksArgs: Codable {
    let notePath: String
}

struct GetBacklinksResult: Codable {
    struct Linked: Codable {
        let source: String
        let lineNumber: Int?
    }
    struct Unlinked: Codable {
        let path: String
        let lineNumber: Int
        let contextLine: String
    }
    let vaultPath: String
    let notePath: String
    let linked: [Linked]
    let unlinked: [Unlinked]
}

func getBacklinks(_ args: GetBacklinksArgs, vaults: [LoadedVault]) async throws -> GetBacklinksResult {
    guard !args.notePath.isEmpty else {
        throw ToolError.missingArgument("note_path")
    }

    for vault in vaults {
        let file: IndexedFile?
        if let f = vault.index.file(forRelativePath: args.notePath) {
            file = f
        } else if let f = vault.index.resolveWikiLink(name: args.notePath) {
            file = f
        } else {
            let withoutExt = args.notePath.hasSuffix(".md")
                ? String(args.notePath.dropLast(3))
                : args.notePath
            file = vault.index.resolveWikiLink(name: withoutExt)
        }

        guard let file = file else { continue }

        let linked = vault.index.linksTo(fileId: file.id)
        let unlinked = vault.index.unlinkedMentions(for: file.filename, excludingFileId: file.id)

        return GetBacklinksResult(
            vaultPath: vault.url.path,
            notePath: file.path,
            linked: linked.map {
                GetBacklinksResult.Linked(
                    source: $0.sourcePath ?? $0.sourceFilename ?? "unknown",
                    lineNumber: $0.lineNumber
                )
            },
            unlinked: unlinked.map {
                GetBacklinksResult.Unlinked(
                    path: $0.file.path,
                    lineNumber: $0.lineNumber,
                    contextLine: $0.contextLine
                )
            }
        )
    }

    throw ToolError.noteNotFound(args.notePath)
}
