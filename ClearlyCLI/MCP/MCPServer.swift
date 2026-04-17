import Foundation
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

        // Block until the process is terminated
        try await Task.sleep(for: .seconds(365 * 24 * 3600))
    }
}
