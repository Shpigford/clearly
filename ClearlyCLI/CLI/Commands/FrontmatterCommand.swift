import ArgumentParser
import ClearlyCore
import Foundation

struct FrontmatterCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "frontmatter",
        abstract: "Return the parsed YAML frontmatter of a note as a flat key-value map.",
        discussion: """
        Reads directly from disk (not the index) so results always reflect
        current file state. Duplicate keys are last-write-wins to match the
        internal flattening behavior.

        Output shape documented in README.md, section "clearly CLI" →
        "Tool reference" → get_frontmatter. Returns
        {has_frontmatter: false, frontmatter: {}} when the note has no
        YAML block.

        EXAMPLES
          # Dump a note's frontmatter
          clearly frontmatter Projects/2026-plan.md

          # Extract a single tag field
          clearly frontmatter Projects/plan.md | jq -r '.frontmatter.status'

          # Skip notes without frontmatter
          clearly list | jq -r '.relative_path' \\
            | xargs -I{} sh -c 'clearly frontmatter "{}" | jq -e ".has_frontmatter"' \\
            2>/dev/null
        """
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Vault-relative path, e.g. 'Projects/2026-plan.md'.")
    var relativePath: String

    @Option(name: .customLong("in-vault"), help: "Optional vault disambiguator (name or path) when multiple vaults are loaded.")
    var inVault: String?

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
            let result = try await getFrontmatter(
                GetFrontmatterArgs(relativePath: relativePath, vault: inVault),
                vaults: vaults
            )
            switch globals.format {
            case .json:
                try Emitter.emit(result, format: .json)
            case .text:
                if !result.hasFrontmatter {
                    Emitter.emitLine("(no frontmatter)")
                } else {
                    for key in result.frontmatter.keys.sorted() {
                        Emitter.emitLine("\(key): \(result.frontmatter[key] ?? "")")
                    }
                }
            }
        } catch let error as ToolError {
            let code = Emitter.emitToolError(error)
            throw ExitCode(code)
        }
    }
}
