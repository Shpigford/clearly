import ArgumentParser
import Foundation

struct HeadingsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "headings",
        abstract: "Extract headings from a note (arrives in Phase 2)."
    )

    func run() async throws {
        FileHandle.standardError.write(
            Data("clearly headings — not yet implemented (Phase 2)\n".utf8)
        )
        throw ExitCode(Exit.usage)
    }
}
