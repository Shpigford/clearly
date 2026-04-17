import ArgumentParser
import Foundation

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Start the Model Context Protocol stdio server."
    )

    @OptionGroup var globals: GlobalOptions

    func run() async throws {
        let vaults: [LoadedVault]
        do {
            vaults = try IndexSet.openIndexes(globals)
        } catch IndexSetError.noVaults {
            FileHandle.standardError.write(Data("""
            No vaults found. Either:
              - Open Clearly and add a vault first (auto-detected via ~/.config/clearly/vaults.json)
              - Pass --vault <path> explicitly

            """.utf8))
            throw ExitCode(Exit.general)
        } catch IndexSetError.pathsMissing {
            FileHandle.standardError.write(Data("Error: No vault paths exist on disk.\n".utf8))
            throw ExitCode(Exit.general)
        } catch IndexSetError.noIndexes {
            FileHandle.standardError.write(Data("""
            Error: Could not open any vault indexes.
            Make sure Clearly has been opened with these vaults at least once.

            """.utf8))
            throw ExitCode(Exit.general)
        }

        try await MCPServer.start(vaults: vaults)
    }
}
