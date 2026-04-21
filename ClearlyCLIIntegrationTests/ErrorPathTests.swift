import Foundation
@testable import ClearlyCore
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

    func testConflictResolverCopiesEveryPendingVersionBeforeResolving() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clearly-conflicts-\(UUID().uuidString)", isDirectory: true)
        let versionsDir = root.appendingPathComponent("versions", isDirectory: true)
        try FileManager.default.createDirectory(at: versionsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let originalURL = root.appendingPathComponent("Note.md")
        try "current".write(to: originalURL, atomically: true, encoding: .utf8)

        let versionTexts = ["version 1", "version 2", "version 3"]
        let versionURLs = try versionTexts.enumerated().map { index, text in
            let url = versionsDir.appendingPathComponent("v\(index).md")
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        var resolvedIndexes: [Int] = []
        let pending = versionURLs.enumerated().map { index, url in
            ConflictResolver.PendingVersion(contentsURL: url) {
                resolvedIndexes.append(index)
            }
        }

        let outcome = try ConflictResolver.resolve(
            versions: pending,
            at: originalURL,
            presenter: nil,
            removeOtherVersions: false
        )

        XCTAssertEqual(outcome?.currentText, "current")
        XCTAssertEqual(outcome?.siblingText, "version 1")
        XCTAssertEqual(resolvedIndexes.sorted(), [0, 1, 2])

        let conflictFiles = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("Note (conflict ") }

        XCTAssertEqual(conflictFiles.count, 3)
        let copiedTexts = try conflictFiles.map { try String(contentsOf: $0, encoding: .utf8) }
        XCTAssertEqual(Set(copiedTexts), Set(versionTexts))
    }
}
