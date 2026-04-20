import ArgumentParser
import ClearlyCore
import Foundation

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Start the Model Context Protocol stdio server.",
        discussion: """
        Runs a JSON-RPC MCP server over stdio, exposing all 9 Clearly tools
        (search_notes, get_backlinks, get_tags, read_note, list_notes,
        get_headings, get_frontmatter, create_note, update_note).

        This is the mode invoked by Claude Desktop, Claude Code, Cursor, and
        other MCP clients. Do not run it interactively — stdout is reserved
        for JSON-RPC frames; the process ends when stdin closes.

        Client config examples are in README.md, section "ClearlyMCP".

        EXAMPLES
          # Typical Claude Desktop config entry (in claude_desktop_config.json):
          #   "clearly": { "command": "/usr/local/bin/clearly", "args": ["mcp"] }

          # Manual smoke test (pipe a JSON-RPC initialize request):
          echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"0.0.1"}}}' | clearly mcp
        """
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
