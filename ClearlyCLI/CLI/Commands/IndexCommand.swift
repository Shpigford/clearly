import ArgumentParser
import Foundation

struct IndexCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "index",
        abstract: "Vault index maintenance (arrives in Phase 5)."
    )

    func run() async throws {
        FileHandle.standardError.write(
            Data("clearly index — not yet implemented (Phase 5)\n".utf8)
        )
        throw ExitCode(Exit.usage)
    }
}
