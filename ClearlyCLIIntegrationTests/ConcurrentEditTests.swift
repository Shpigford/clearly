import Foundation
import ClearlyCore
import MCP
import CryptoKit
import XCTest

/// Coverage of the new write-coordination + optimistic-concurrency
/// behavior on `update_note`. Both surfaces (the editor save path and
/// MCP write tools) now route writes through `CoordinatedFileIO`, and
/// `update_note` accepts an optional `expected_content_hash` that
/// rejects stale-base writes.
final class ConcurrentEditTests: XCTestCase {
    var harness: TestVaultHarness!

    override func setUp() async throws {
        harness = try await TestVaultHarness()
    }

    override func tearDown() async throws {
        await harness?.tearDown()
        harness = nil
    }

    private struct UpdateResult: Decodable {
        let contentHash: String
    }

    private func sha256(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func testExpectedHashMismatchReturnsStaleContent() async throws {
        let url = harness.vaultURL.appendingPathComponent("Notes/Linker.md")
        // Mutate the file out from under us so the agent's "expected"
        // hash is now stale.
        try "wrong base".data(using: .utf8)!.write(to: url, options: .atomic)
        let staleHash = String(repeating: "0", count: 64)

        let payload = try await harness.callToolExpectingError(
            "update_note",
            arguments: [
                "relative_path": .string("Notes/Linker.md"),
                "content": .string("# replaced\n"),
                "mode": .string("replace"),
                "expected_content_hash": .string(staleHash),
            ]
        )
        XCTAssertEqual(payload.error, "stale_content")
    }

    func testExpectedHashMatchAllowsUpdate() async throws {
        let url = harness.vaultURL.appendingPathComponent("Notes/Linker.md")
        let currentHash = try sha256(url)

        let result = try await harness.callTool(
            "update_note",
            arguments: [
                "relative_path": .string("Notes/Linker.md"),
                "content": .string("# replaced\n"),
                "mode": .string("replace"),
                "expected_content_hash": .string(currentHash),
            ],
            as: UpdateResult.self
        )
        let actual = try sha256(url)
        XCTAssertEqual(actual, result.contentHash, "tool's reported hash must equal on-disk hash")
        XCTAssertNotEqual(actual, currentHash, "file should have changed")
    }

    func testMissingExpectedHashStillSucceedsForBackwardCompatibility() async throws {
        // Legacy callers don't send expected_content_hash. The tool must
        // still accept the call and write through.
        let result = try await harness.callTool(
            "update_note",
            arguments: [
                "relative_path": .string("Notes/Linker.md"),
                "content": .string("legacy update\n"),
                "mode": .string("replace"),
            ],
            as: UpdateResult.self
        )
        let onDisk = try sha256(harness.vaultURL.appendingPathComponent("Notes/Linker.md"))
        XCTAssertEqual(onDisk, result.contentHash)
    }

    /// Two writers racing the same file via `CoordinatedFileIO` must
    /// produce a final state matching exactly one of the two payloads —
    /// not a torn mix. (This is the OS file-coordinator's contract; we
    /// just verify our paths actually go through it.)
    func testConcurrentCoordinatedWritesProduceOneOrTheOtherNotTorn() async throws {
        let url = harness.vaultURL.appendingPathComponent("Notes/Linker.md")
        let payloadA = String(repeating: "A", count: 4096) + "\n"
        let payloadB = String(repeating: "B", count: 4096) + "\n"

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                try? CoordinatedFileIO.write(Data(payloadA.utf8), to: url)
            }
            group.addTask {
                try? CoordinatedFileIO.write(Data(payloadB.utf8), to: url)
            }
        }

        let final = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(
            final == payloadA || final == payloadB,
            "Coordinated writes must serialize; final must equal one full payload, not a mix"
        )
    }
}
