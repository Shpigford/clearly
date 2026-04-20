import ArgumentParser
import ClearlyCore
import Foundation

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List notes in loaded vault(s). Emits NDJSON (one record per line).",
        discussion: """
        Walks the filesystem fresh every call (not the index) so results
        always reflect current on-disk state. Each record carries vault,
        relative_path, size_bytes, modified_at.

        Use --under to scope to a subdirectory prefix and --in-vault to
        scope to a single vault when multiple are loaded.

        Output shape documented in README.md, section "clearly CLI" →
        "Tool reference" → list_notes.

        EXAMPLES
          # Every note across every vault
          clearly list

          # Only daily notes
          clearly list --under Daily/

          # Count notes per vault
          clearly list | jq -r '.vault' | sort | uniq -c

          # Piping relative paths into another clearly command
          clearly list --under Projects/ | jq -r '.relative_path' \\
            | xargs -I{} clearly headings {}
        """
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
                message: "Unable to open any vault index: \(error.localizedDescription)",
                extra: ["bundle_id": globals.bundleID]
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
