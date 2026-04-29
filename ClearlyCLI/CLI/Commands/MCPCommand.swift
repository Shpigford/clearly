import ArgumentParser
import ClearlyCore
import Foundation
import MCP

struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Start the Model Context Protocol stdio server (default), or inspect registered tools.",
        discussion: """
        Runs a JSON-RPC MCP server over stdio, exposing Clearly tools
        (semantic_search, search_notes, get_backlinks, get_tags, read_note,
        list_notes, get_headings, get_frontmatter, create_note,
        update_note). Use `clearly mcp tools` for the live registered set.

        This is the mode invoked by Claude Desktop, Claude Code, Cursor, and
        other MCP clients. Do not run it interactively — stdout is reserved
        for JSON-RPC frames; the process ends when stdin closes.

        Subcommands
          serve    Start the stdio server (default; same as `clearly mcp`).
          tools    Print every registered tool's name, description, and
                   input/output schema as JSON. Useful for debugging an
                   MCP client config or generating tool reference docs.

        EXAMPLES
          # Typical Claude Desktop config entry (in claude_desktop_config.json):
          #   "clearly": { "command": "/usr/local/bin/clearly", "args": ["mcp"] }

          # Manual smoke test (pipe a JSON-RPC initialize request):
          echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"0.0.1"}}}' | clearly mcp

          # List every registered tool:
          clearly mcp tools | jq -r '.[].name'

          # Inspect read-only-only set:
          clearly mcp tools --read-only
        """,
        subcommands: [MCPServeCommand.self, MCPToolsCommand.self],
        defaultSubcommand: MCPServeCommand.self
    )
}

struct MCPServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start the MCP stdio server (default; same as `clearly mcp`).",
        discussion: """
        Reads JSON-RPC frames from stdin, writes responses to stdout. Logs
        go to stderr. The process exits when stdin closes.
        """
    )

    @OptionGroup var globals: GlobalOptions

    @Flag(name: .customLong("read-only"), help: "Expose only read-only MCP tools.")
    var readOnly: Bool = false

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

        try await MCPServer.start(vaults: vaults, readOnly: readOnly)
    }
}

struct MCPToolsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tools",
        abstract: "Print registered MCP tools and their schemas as JSON.",
        discussion: """
        Emits a single JSON array. Each entry is an MCP `Tool` object with
        name, description, input schema, output schema, and annotations.
        Honors `--read-only` to show only the read-only tool set.

        EXAMPLES
          clearly mcp tools | jq -r '.[].name'
          clearly mcp tools --read-only | jq '.[] | {name, description}'
        """
    )

    @OptionGroup var globals: GlobalOptions

    @Flag(name: .customLong("read-only"), help: "Show only the read-only tool set.")
    var readOnly: Bool = false

    func run() async throws {
        let vaults: [LoadedVault]
        do {
            vaults = try IndexSet.openIndexes(globals)
        } catch {
            Emitter.emitError(
                "no_vaults",
                message: "Unable to open any vault index: \(error.localizedDescription)",
                extra: ["bundle_id": globals.bundleID]
            )
            throw ExitCode(Exit.general)
        }

        let tools = ToolRegistry.listTools(vaults: vaults, readOnly: readOnly)

        switch globals.format {
        case .json:
            // MCP's wire format uses camelCase keys (`inputSchema`,
            // `outputSchema`, `readOnlyHint`, …) so the dump matches what
            // a client sees over JSON-RPC. The shared Emitter helper
            // converts to snake_case for our own structured output, which
            // would silently rename these keys and confuse anyone
            // comparing against the spec.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(tools)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        case .text:
            for tool in tools {
                Emitter.emitLine(tool.name)
            }
        }
    }
}
