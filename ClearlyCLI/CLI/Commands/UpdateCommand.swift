import ArgumentParser
import Foundation

struct UpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update an existing note (arrives in Phase 3)."
    )

    func run() async throws {
        FileHandle.standardError.write(
            Data("clearly update — not yet implemented (Phase 3)\n".utf8)
        )
        throw ExitCode(Exit.usage)
    }
}
