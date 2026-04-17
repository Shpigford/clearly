import ArgumentParser
import Foundation

struct VaultsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vaults",
        abstract: "List configured vaults (arrives in Phase 5)."
    )

    func run() async throws {
        FileHandle.standardError.write(
            Data("clearly vaults — not yet implemented (Phase 5)\n".utf8)
        )
        throw ExitCode(Exit.usage)
    }
}
