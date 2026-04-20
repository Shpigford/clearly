import ArgumentParser
import ClearlyCore
import Foundation

extension UpdateMode: ExpressibleByArgument {}

struct UpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update an existing note with replace, append, or prepend mode.",
        discussion: """
        Modes:
          • replace  — overwrite the entire file
          • append   — add content at the end, inserting a leading newline
                       if the file does not already end with one
          • prepend  — insert content at the beginning; if the file has
                       YAML frontmatter, content is inserted AFTER the
                       closing "---" block, never in front of it

        Fails with exit 3 / error note_not_found if the note doesn't
        exist — use `clearly create` for new notes. Path traversal checks
        match `clearly create`.

        Provide content via --content "<string>" or --from-stdin (mutually
        exclusive).

        Output shape documented in README.md, section "clearly CLI" →
        "Tool reference" → update_note.

        EXAMPLES
          # Append a line to today's daily note
          clearly update Daily/2026-04-17.md --mode append --content $'\\n- New idea'

          # Replace whole file from stdin
          cat revised.md | clearly update Notes/plan.md --mode replace --from-stdin

          # Prepend a heading to a note with frontmatter — inserted AFTER
          # the --- block, not in front of it
          clearly update Strategy/pricing.md --mode prepend --content $'## Summary\\n\\n'
        """
    )

    @OptionGroup var globals: GlobalOptions

    @Argument(help: "Vault-relative path, e.g. 'Daily/2026-04-17.md'.")
    var relativePath: String

    @Option(name: .long, help: "Update mode: replace, append, or prepend.")
    var mode: UpdateMode

    @Option(name: .long, help: "New content as a string. Mutually exclusive with --from-stdin.")
    var content: String?

    @Flag(name: .customLong("from-stdin"), help: "Read content from stdin.")
    var fromStdin: Bool = false

    @Option(name: .customLong("in-vault"), help: "Vault name or path.")
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
            let result = try await updateNote(
                UpdateNoteArgs(relativePath: relativePath, content: body, mode: mode, vault: inVault),
                vaults: vaults
            )
            try Emitter.emit(result, format: globals.format)
        } catch let error as ToolError {
            let code = Emitter.emitToolError(error)
            throw ExitCode(code)
        }
    }
}
