import ArgumentParser
import Foundation

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search notes by query (arrives in Phase 4)."
    )

    func run() async throws {
        FileHandle.standardError.write(
            Data("clearly search — not yet implemented (Phase 4)\n".utf8)
        )
        throw ExitCode(Exit.usage)
    }
}
