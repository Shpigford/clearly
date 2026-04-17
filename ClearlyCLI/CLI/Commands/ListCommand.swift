import ArgumentParser
import Foundation

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List notes in loaded vault(s). Emits NDJSON (one record per line)."
    )

    @OptionGroup var globals: GlobalOptions

    @Option(help: "Vault-relative directory prefix to filter by, e.g. 'Daily/'.")
    var under: String?

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
            let result = try await listNotes(
                ListNotesArgs(under: under, vault: inVault),
                vaults: vaults
            )
            switch globals.format {
            case .json:
                for note in result.notes {
                    try Emitter.emitNDJSONRecord(note)
                }
            case .text:
                for note in result.notes {
                    Emitter.emitLine("\(note.relativePath)\t\(note.sizeBytes)\t\(note.modifiedAt)")
                }
            }
        } catch let error as ToolError {
            let code = Emitter.emitToolError(error)
            throw ExitCode(code)
        }
    }
}
