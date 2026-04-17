import ArgumentParser
import Foundation

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List notes in a vault (arrives in Phase 2)."
    )

    func run() async throws {
        FileHandle.standardError.write(
            Data("clearly list — not yet implemented (Phase 2)\n".utf8)
        )
        throw ExitCode(Exit.usage)
    }
}
