import ArgumentParser
import Foundation

extension UpdateMode: ExpressibleByArgument {}

struct UpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update an existing note with replace, append, or prepend mode."
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
            Emitter.emitError("no_vaults", message: "Unable to open any vault index: \(error.localizedDescription)")
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
