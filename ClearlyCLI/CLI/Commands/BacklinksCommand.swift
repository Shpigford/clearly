import ArgumentParser
import Foundation

struct BacklinksCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "backlinks",
        abstract: "List backlinks for a note (arrives in Phase 4)."
    )

    func run() async throws {
        FileHandle.standardError.write(
            Data("clearly backlinks — not yet implemented (Phase 4)\n".utf8)
        )
        throw ExitCode(Exit.usage)
    }
}
