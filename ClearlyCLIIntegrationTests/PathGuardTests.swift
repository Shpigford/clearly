import Foundation
import ClearlyCore
import MCP
import XCTest

/// Path-safety matrix. PathGuard distinguishes two error classes:
///   • `path_outside_vault` — the input would resolve outside the vault root
///     (traversal, absolute paths, unicode dotdot lookalikes, Windows `..\\`).
///   • `invalid_argument`   — the input is malformed in a way that's never
///     valid regardless of vault layout (null bytes, shell metacharacters).
///
/// Both reject writes AND reads before any filesystem I/O.
final class PathGuardTests: XCTestCase {
    var harness: TestVaultHarness!

    override func setUp() async throws {
        harness = try await TestVaultHarness()
    }

    override func tearDown() async throws {
        await harness?.tearDown()
        harness = nil
    }

    static let traversalInputs: [(label: String, path: String)] = [
        ("classic dotdot", "../outside.md"),
        ("nested dotdot", "Notes/../../escape.md"),
        ("absolute root", "/etc/passwd"),
        ("absolute tmp", "/tmp/oops.md"),
        ("windows-style backslash", "..\\escape.md"),
        ("unicode two-dot leader", "\u{2025}/escape.md"),
        ("unicode fullwidth dot", "\u{FF0E}\u{FF0E}/escape.md"),
    ]

    static let malformedInputs: [(label: String, path: String)] = [
        ("shell command substitution", "$(whoami).md"),
        ("backtick", "`id`.md"),
        ("null byte", "note\u{00}.md"),
    ]

    func testCreateNoteRejectsTraversal() async throws {
        for (label, input) in Self.traversalInputs {
            let err = try await harness.callToolExpectingError(
                "create_note",
                arguments: [
                    "relative_path": .string(input),
                    "content": .string("x")
                ]
            )
            XCTAssertEqual(
                err.error, "path_outside_vault",
                "expected path_outside_vault for \(label) input '\(input)'; got \(err.error)"
            )
        }
    }

    func testCreateNoteRejectsMalformed() async throws {
        for (label, input) in Self.malformedInputs {
            let err = try await harness.callToolExpectingError(
                "create_note",
                arguments: [
                    "relative_path": .string(input),
                    "content": .string("x")
                ]
            )
            XCTAssertEqual(
                err.error, "invalid_argument",
                "expected invalid_argument for \(label) input '\(input)'; got \(err.error)"
            )
        }
    }

    func testReadNoteRejectsTraversal() async throws {
        for (label, input) in Self.traversalInputs {
            let err = try await harness.callToolExpectingError(
                "read_note",
                arguments: ["relative_path": .string(input)]
            )
            XCTAssertEqual(
                err.error, "path_outside_vault",
                "expected path_outside_vault for \(label) input '\(input)'; got \(err.error)"
            )
        }
    }

    func testReadNoteRejectsMalformed() async throws {
        for (label, input) in Self.malformedInputs {
            let err = try await harness.callToolExpectingError(
                "read_note",
                arguments: ["relative_path": .string(input)]
            )
            XCTAssertEqual(
                err.error, "invalid_argument",
                "expected invalid_argument for \(label) input '\(input)'; got \(err.error)"
            )
        }
    }
}
