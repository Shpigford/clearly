import ArgumentParser
import ClearlyCore
import Foundation

struct HeadingsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "headings",
        abstract: "Return the heading outline of a note.",
        discussion: """
        Sourced from the vault's index, so the note must have been indexed
        at least once. Returns an array of {level, text, line_number},
        level 1–6.

        Output shape documented in README.md, section "clearly CLI" →
        "Tool reference" → get_headings.

        EXAMPLES
          # Print the outline as JSON
          clearly headings Strategy/pricing.md

          # Human-readable outline
          clearly headings Strategy/pricing.md --format text

          # Count H2s in a note
          clearly headings 'Projects/plan.md' | jq '[.headings[] | select(.level == 2)] | length'
        """
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Vault-relative path, e.g. 'Strategy/pricing.md'.")
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
            let result = try await getHeadings(
                GetHeadingsArgs(relativePath: relativePath, vault: inVault),
                vaults: vaults
            )
            switch globals.format {
            case .json:
                try Emitter.emit(result, format: .json)
            case .text:
                for h in result.headings {
                    let prefix = String(repeating: "#", count: h.level)
                    Emitter.emitLine("\(prefix) \(h.text)\t(line \(h.lineNumber))")
                }
            }
        } catch let error as ToolError {
            let code = Emitter.emitToolError(error)
            throw ExitCode(code)
        }
    }
}
