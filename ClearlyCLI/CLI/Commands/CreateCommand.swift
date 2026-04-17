import ArgumentParser
import Foundation

struct CreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new note at the given vault-relative path."
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
            Emitter.emitError("no_vaults", message: "Unable to open any vault index: \(error.localizedDescription)")
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
