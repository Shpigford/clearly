import ArgumentParser
import Foundation

struct ReadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: "Read a note by vault-relative path, with optional line range."
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Vault-relative path, e.g. 'Daily/2026-04-16.md'.")
    var relativePath: String

    @Option(name: .customLong("start-line"), help: "1-based line number to start reading from.")
    var startLine: Int?

    @Option(name: .customLong("end-line"), help: "1-based line number to stop reading at (inclusive).")
    var endLine: Int?

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
            let result = try await readNote(
                ReadNoteArgs(
                    relativePath: relativePath,
                    startLine: startLine,
                    endLine: endLine,
                    vault: inVault
                ),
                vaults: vaults
            )
            switch globals.format {
            case .json:
                try Emitter.emit(result, format: .json)
            case .text:
                Emitter.emitLine(result.content)
            }
        } catch let error as ToolError {
            let code = Emitter.emitToolError(error)
            throw ExitCode(code)
        }
    }
}
