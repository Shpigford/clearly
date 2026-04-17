import ArgumentParser
import Foundation

struct ReadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: "Read a note by relative path (arrives in Phase 2)."
    )

    func run() async throws {
        FileHandle.standardError.write(
            Data("clearly read — not yet implemented (Phase 2)\n".utf8)
        )
        throw ExitCode(Exit.usage)
    }
}
