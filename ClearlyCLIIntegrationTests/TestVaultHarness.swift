import Foundation
import ClearlyCore
import MCP
import XCTest

/// Spins up a temporary copy of the bundled FixtureVault/, opens a VaultIndex
/// backed by an isolated per-test bundle-id (so no real AppSupport state is
/// touched), and wires a paired InMemoryTransport MCP Client + Server with the
/// real ToolRegistry + Handlers. Clean-up removes every temp artefact.
///
/// One harness per XCTestCase.setUp().
final class TestVaultHarness {
    let vaultURL: URL
    let bundleID: String
    let loadedVaults: [LoadedVault]
    let client: Client
    let server: Server

    private let tempRoot: URL
    private let indexRoot: URL

    init() async throws {
        let uuid = UUID().uuidString
        self.bundleID = "com.sabotage.clearly.tests.\(uuid)"

        self.tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("clearly-integration-\(uuid)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        // Copy FixtureVault/ from the test bundle into the temp root
        let bundle = Bundle(for: TestVaultHarness.self)
        guard let fixtureURL = bundle.url(forResource: "FixtureVault", withExtension: nil) else {
            throw HarnessError.fixtureMissing
        }
        self.vaultURL = tempRoot.appendingPathComponent("FixtureVault", isDirectory: true)
        try FileManager.default.copyItem(at: fixtureURL, to: vaultURL)

        // Isolated AppSupport root for this test's index
        self.indexRoot = tempRoot.appendingPathComponent("AppSupport", isDirectory: true)
        try FileManager.default.createDirectory(at: indexRoot, withIntermediateDirectories: true)

        // VaultIndex uses the real AppSupport path via `Self.indexDirectory(bundleIdentifier:)`.
        // We can't redirect it without production code changes, so the unique
        // bundleID above keeps each test run on its own sub-directory. Cleanup
        // is best-effort via the bundleID-specific dir in tearDown.
        let index = try VaultIndex(locationURL: vaultURL, bundleIdentifier: bundleID)
        index.indexAllFiles()

        self.loadedVaults = [LoadedVault(index: index, url: vaultURL)]

        // Build the MCP pair
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()

        let server = Server(
            name: "clearly-test",
            version: "1.0.0",
            capabilities: .init(tools: .init(listChanged: false))
        )
        let tools = ToolRegistry.listTools(vaults: loadedVaults)
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: tools)
        }
        let vaults = loadedVaults
        await server.withMethodHandler(CallTool.self) { params in
            await Handlers.dispatch(params: params, vaults: vaults)
        }

        let client = Client(name: "clearly-test-client", version: "1.0.0")

        try await server.start(transport: serverTransport)
        try await client.connect(transport: clientTransport)

        self.server = server
        self.client = client
    }

    func tearDown() async {
        await client.disconnect()
        await server.stop()
        // Remove the bundleID-scoped index directory that VaultIndex created
        // under ~/Library/Application Support/<bundleID>/.
        let realIndexDir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent(bundleID, isDirectory: true)
        if let realIndexDir {
            try? FileManager.default.removeItem(at: realIndexDir)
        }
        try? FileManager.default.removeItem(at: tempRoot)
    }

    enum HarnessError: Error {
        case fixtureMissing
    }
}

// MARK: - Helpers

extension TestVaultHarness {
    /// Invoke a tool over the paired MCP transport and decode the JSON text
    /// content block as `T`. Fails the test on any transport/decode error.
    func callTool<T: Decodable>(
        _ name: String,
        arguments: [String: Value] = [:],
        as type: T.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> T {
        let (content, isError) = try await client.callTool(name: name, arguments: arguments)
        XCTAssertFalse(
            isError ?? false,
            "\(name) returned isError=true; content=\(content)",
            file: file,
            line: line
        )
        guard case let .text(jsonString, _, _) = content.first else {
            XCTFail("\(name) returned non-text content: \(content)", file: file, line: line)
            throw HarnessError.fixtureMissing
        }
        let data = Data(jsonString.utf8)
        return try JSONDecoder.snakeCaseDecoder.decode(T.self, from: data)
    }

    /// Invoke a tool expected to fail. Returns the decoded error payload.
    func callToolExpectingError(
        _ name: String,
        arguments: [String: Value] = [:],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> ErrorPayload {
        let (content, isError) = try await client.callTool(name: name, arguments: arguments)
        XCTAssertTrue(
            isError ?? false,
            "\(name) was expected to set isError=true; content=\(content)",
            file: file,
            line: line
        )
        guard case let .text(jsonString, _, _) = content.first else {
            XCTFail("\(name) returned non-text content: \(content)", file: file, line: line)
            throw HarnessError.fixtureMissing
        }
        let data = Data(jsonString.utf8)
        return try JSONDecoder().decode(ErrorPayload.self, from: data)
    }
}

struct ErrorPayload: Decodable {
    let error: String
    let message: String
}

extension JSONDecoder {
    static var snakeCaseDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }
}
