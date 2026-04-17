import ArgumentParser
import Foundation

struct TagsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tags",
        abstract: "List tags (no argument) or files for a tag (with argument). Emits NDJSON in JSON mode."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Optional specific tag (without '#' prefix). Omit to list all tags.")
    var tag: String?

    func run() async throws {
        let vaults: [LoadedVault]
        do {
            vaults = try IndexSet.openIndexes(globals)
        } catch {
            Emitter.emitError(
                "no_vaults",
                message: "Unable to open any vault index: \(error.localizedDescription)"
            )
            throw ExitCode(Exit.general)
        }

        do {
            let result = try await getTags(GetTagsArgs(tag: tag), vaults: vaults)
            switch globals.format {
            case .json:
                switch result.mode {
                case .all:
                    for entry in result.allTags ?? [] {
                        try Emitter.emitNDJSONRecord(entry)
                    }
                case .byTag:
                    for file in result.files ?? [] {
                        try Emitter.emitNDJSONRecord(file)
                    }
                }
            case .text:
                switch result.mode {
                case .all:
                    for entry in result.allTags ?? [] {
                        Emitter.emitLine("#\(entry.tag)\t\(entry.count)")
                    }
                case .byTag:
                    for file in result.files ?? [] {
                        Emitter.emitLine("\(file.vault)\t\(file.relativePath)")
                    }
                }
            }
        } catch let error as ToolError {
            let code = Emitter.emitToolError(error)
            throw ExitCode(code)
        }
    }
}
