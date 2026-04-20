import Foundation
import ClearlyCore
import MCP

enum MCPServer {
    static func start(vaults: [LoadedVault]) async throws {
        let server = Server(
            name: "clearly",
            version: "1.0.0",
            capabilities: .init(tools: .init(listChanged: false))
        )

        let tools = ToolRegistry.listTools(vaults: vaults)
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            await Handlers.dispatch(params: params, vaults: vaults)
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)

        // Block until stdin closes (MCP client disconnects) — the transport
        // reports EOF which completes the server lifecycle. Previously this
        // slept for a year regardless of transport state, which made scripted
        // JSON-RPC smoke tests hang. `waitUntilCompleted` returns promptly on
        // clean disconnect and keeps blocking during normal client use.
        await server.waitUntilCompleted()
    }
}
