import Foundation
import ClearlyCore
import MCP
import XCTest

/// Exercise every ToolError case end-to-end via the MCP path.
final class ErrorPathTests: XCTestCase {
    var harness: TestVaultHarness!

    override func setUp() async throws {
        harness = try await TestVaultHarness()
    }

    override func tearDown() async throws {
        await harness?.tearDown()
        harness = nil
    }

    func testReadNoteMissing() async throws {
        let err = try await harness.callToolExpectingError(
            "read_note",
            arguments: ["relative_path": .string("does/not/exist.md")]
        )
        XCTAssertEqual(err.error, "note_not_found")
    }

    func testCreateNoteConflict() async throws {
        struct Ignored: Decodable {}
        _ = try await harness.callTool(
            "create_note",
            arguments: [
                "relative_path": .string("Inbox/dup.md"),
                "content": .string("first")
            ],
            as: Ignored.self
        )
        let err = try await harness.callToolExpectingError(
            "create_note",
            arguments: [
                "relative_path": .string("Inbox/dup.md"),
                "content": .string("second")
            ]
        )
        XCTAssertEqual(err.error, "note_exists")
    }

    func testUpdateNoteInvalidMode() async throws {
        let err = try await harness.callToolExpectingError(
            "update_note",
            arguments: [
                "relative_path": .string("Daily/2026-04-17.md"),
                "mode": .string("not-a-mode"),
                "content": .string("x")
            ]
        )
        XCTAssertEqual(err.error, "invalid_argument")
    }

    func testUnknownToolReturnsStableError() async throws {
        let err = try await harness.callToolExpectingError(
            "not_a_real_tool"
        )
        XCTAssertEqual(err.error, "unknown_tool")
    }
}
