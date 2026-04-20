import ArgumentParser
import ClearlyCore
import Foundation

struct ReadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: "Read a note by vault-relative path, with optional line range.",
        discussion: """
        Returns a single JSON object with content, SHA-256 content_hash,
        size_bytes, modified_at (ISO-8601 w/ fractional seconds), parsed
        frontmatter (flat key-value), headings, tags, and an echoed
        line_range when --start-line / --end-line are used.

        When multiple vaults are loaded and the relative path exists in more
        than one, pass --in-vault to disambiguate (exit code 5 otherwise).
        Use exit code 3 to detect "not found".

        Output shape documented in README.md, section "clearly CLI" →
        "Tool reference" → read_note.

        EXAMPLES
          # Read a whole note
          clearly read Daily/2026-04-16.md

          # Read only lines 10–30
          clearly read notes/longer-note.md --start-line 10 --end-line 30

          # Extract the SHA-256 hash for cache invalidation
          clearly read Projects/plan.md | jq -r '.content_hash'

          # Two-vault setup: scope the lookup
          clearly read README.md --in-vault Work
        """
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
                message: "Unable to open any vault index: \(error.localizedDescription)",
                extra: ["bundle_id": globals.bundleID]
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
