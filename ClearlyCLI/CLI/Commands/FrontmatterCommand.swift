import ArgumentParser
import Foundation

struct FrontmatterCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "frontmatter",
        abstract: "Return the parsed YAML frontmatter of a note as a flat key-value map."
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
                message: "Unable to open any vault index: \(error.localizedDescription)"
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
