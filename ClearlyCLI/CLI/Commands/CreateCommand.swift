import ArgumentParser
import Foundation

struct CreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new note (arrives in Phase 3)."
    )

    func run() async throws {
        FileHandle.standardError.write(
            Data("clearly create — not yet implemented (Phase 3)\n".utf8)
        )
        throw ExitCode(Exit.usage)
    }
}
