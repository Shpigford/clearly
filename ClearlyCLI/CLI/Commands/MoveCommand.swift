import ArgumentParser
import ClearlyCore
import Foundation

struct MoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move",
        abstract: "Move or rename a note within a vault, rewriting every inbound [[wiki-link]].",
        discussion: """
        Vault-aware move. Reads every note that links to the source,
        rewrites those `[[wiki-links]]` to point at the new path
        (preserving heading anchors and aliases), then moves the file
        and updates the SQLite index without losing inbound link
        relationships.

        Fails with exit 5 / error note_exists if the destination already
        exists, exit 3 / note_not_found if the source doesn't exist.

        EXAMPLES
          # Rename in place
          clearly move Inbox/draft.md Notes/published.md

          # Move into a subfolder, keeping the filename
          clearly move Inbox/draft.md Archive/2026/draft.md
        """
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Source vault-relative path.")
    var fromPath: String

    @Argument(help: "Destination vault-relative path.")
    var toPath: String

    @Option(name: .customLong("in-vault"), help: "Vault name or path (required when multiple vaults are loaded).")
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
            let result = try await moveNote(
                MoveNoteArgs(fromPath: fromPath, toPath: toPath, vault: inVault),
                vaults: vaults
            )
            try Emitter.emit(result, format: globals.format)
        } catch let error as ToolError {
            let code = Emitter.emitToolError(error)
            throw ExitCode(code)
        }
    }
}
