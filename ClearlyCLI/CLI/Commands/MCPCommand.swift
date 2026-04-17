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
            let msg = "No vaults found. Either:\n"
                + "  - Open Clearly and add a vault first (auto-detected via ~/.config/clearly/vaults.json)\n"
                + "  - Pass --vault <path> explicitly\n"
            FileHandle.standardError.write(Data(msg.utf8))
            throw ExitCode(Exit.general)
        } catch IndexSetError.pathsMissing {
            FileHandle.standardError.write(Data("Error: No vault paths exist on disk.\n".utf8))
            throw ExitCode(Exit.general)
        } catch IndexSetError.noIndexes {
            let msg = "Error: Could not open any vault indexes.\n"
                + "Make sure Clearly has been opened with these vaults at least once.\n"
            FileHandle.standardError.write(Data(msg.utf8))
            throw ExitCode(Exit.general)
        }

        try await MCPServer.start(vaults: vaults)
    }
}
