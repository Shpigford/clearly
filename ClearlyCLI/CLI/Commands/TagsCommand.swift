import ArgumentParser
import ClearlyCore
import Foundation

struct TagsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tags",
        abstract: "List tags (no argument) or files for a tag (with argument). Emits NDJSON in JSON mode.",
        discussion: """
        Two modes, selected by whether a tag argument is provided:

          • No argument  — emits {tag, count} records across all vaults
            (mode: all).
          • With a tag   — emits {vault, vault_path, relative_path} records
            listing every note that carries the tag (mode: by_tag).

        Tags come from both inline #hashtags and YAML frontmatter `tags:`
        entries. The argument must NOT include the leading "#".

        Output shape documented in README.md, section "clearly CLI" →
        "Tool reference" → get_tags.

        EXAMPLES
          # Top 20 tags by count
          clearly tags | jq -s 'sort_by(-.count) | .[:20]'

          # All notes tagged #architecture
          clearly tags architecture

          # Human-readable count view
          clearly tags --format text | sort -k2 -nr | head -20
        """
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
                message: "Unable to open any vault index: \(error.localizedDescription)",
                extra: ["bundle_id": globals.bundleID]
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
