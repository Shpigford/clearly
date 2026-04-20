import ArgumentParser
import ClearlyCore
import Foundation

struct CreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new note at the given vault-relative path.",
        discussion: """
        Parent directories are created automatically. Fails with exit 5 /
        error note_exists if the note already exists — use `clearly update`
        to modify existing notes. Path traversal attempts (../, absolute
        paths, unicode lookalikes) are rejected with exit 4 /
        error path_outside_vault.

        When multiple vaults are loaded, --in-vault is required. Provide
        content via --content "<string>" or --from-stdin (mutually
        exclusive). Content starting with "---" must use --from-stdin
        (swift-argument-parser parses it as a flag otherwise).

        Output shape documented in README.md, section "clearly CLI" →
        "Tool reference" → create_note.

        EXAMPLES
          # Inline content
          clearly create Daily/2026-04-17.md --content "# Today\\n\\nNotes..."

          # Pipe content from stdin (recommended for anything non-trivial)
          cat draft.md | clearly create Inbox/draft.md --from-stdin

          # Two-vault setup
          clearly create Notes/idea.md --content "..." --in-vault Work
        """
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Vault-relative path, e.g. 'Daily/2026-04-17.md'.")
    var relativePath: String

    @Option(name: .long, help: "Note content as a string. Mutually exclusive with --from-stdin.")
    var content: String?

    @Flag(name: .customLong("from-stdin"), help: "Read content from stdin.")
    var fromStdin: Bool = false

    @Option(name: .customLong("in-vault"), help: "Vault name or path (required when multiple vaults are loaded).")
    var inVault: String?

    func run() async throws {
        let body: String
        if let c = content {
            guard !fromStdin else {
                Emitter.emitError("invalid_argument", message: "--content and --from-stdin are mutually exclusive")
                throw ExitCode(Exit.usage)
            }
            body = c
        } else if fromStdin {
            body = readAllStdin()
        } else {
            Emitter.emitError("missing_argument", message: "Provide --content or --from-stdin")
            throw ExitCode(Exit.usage)
        }

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
            let result = try await createNote(
                CreateNoteArgs(relativePath: relativePath, content: body, vault: inVault),
                vaults: vaults
            )
            try Emitter.emit(result, format: globals.format)
        } catch let error as ToolError {
            let code = Emitter.emitToolError(error)
            throw ExitCode(code)
        }
    }
}
