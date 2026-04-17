import ArgumentParser
import Foundation

struct HeadingsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "headings",
        abstract: "Return the heading outline of a note."
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
                message: "Unable to open any vault index: \(error.localizedDescription)"
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
