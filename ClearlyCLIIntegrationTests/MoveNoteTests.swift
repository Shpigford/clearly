import Foundation
import ClearlyCore
import MCP
import XCTest

/// End-to-end coverage of `move_note`. Verifies the source file moves,
/// inbound `[[wiki-links]]` are rewritten in every linking source file,
/// the SQLite index keeps the same `file_id` (so backlink rows survive),
/// and existing GUI-side state remap continues to work.
final class MoveNoteTests: XCTestCase {
    var harness: TestVaultHarness!

    override func setUp() async throws {
        harness = try await TestVaultHarness()
    }

    override func tearDown() async throws {
        await harness?.tearDown()
        harness = nil
    }

    private struct Rewrite: Decodable {
        let relativePath: String
        let count: Int
    }
    private struct Result: Decodable {
        let vault: String
        let from: String
        let to: String
        let linksRewritten: [Rewrite]
    }

    /// Fixture vault has `Notes/Linker.md` linking to `Link Target` via
    /// `[[Link Target]]` and `[[Link Target|custom display]]`. After
    /// moving `Notes/Link Target.md` → `Archived/Link Target.md`, the
    /// linker file's wiki-links must point at the new path while
    /// preserving the alias.
    func testMovesFileAndRewritesInboundWikiLinks() async throws {
        let result = try await harness.callTool(
            "move_note",
            arguments: [
                "from_path": .string("Notes/Link Target.md"),
                "to_path": .string("Archived/Link Target.md"),
            ],
            as: Result.self
        )

        XCTAssertEqual(result.from, "Notes/Link Target.md")
        XCTAssertEqual(result.to, "Archived/Link Target.md")

        // Source moved on disk.
        let oldURL = harness.vaultURL.appendingPathComponent("Notes/Link Target.md")
        let newURL = harness.vaultURL.appendingPathComponent("Archived/Link Target.md")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))

        // Linker file's content was rewritten; its rewrite count is in the response.
        let linkerURL = harness.vaultURL.appendingPathComponent("Notes/Linker.md")
        let linkerContent = try String(contentsOf: linkerURL, encoding: .utf8)
        XCTAssertTrue(
            linkerContent.contains("[[Archived/Link Target]]"),
            "expected wiki-link to be rewritten; got: \(linkerContent)"
        )
        XCTAssertTrue(
            linkerContent.contains("[[Archived/Link Target|custom display]]"),
            "expected aliased wiki-link to be rewritten preserving the alias"
        )
        XCTAssertFalse(linkerContent.contains("[[Link Target]]"))

        let linkerRewrite = result.linksRewritten.first { $0.relativePath == "Notes/Linker.md" }
        XCTAssertNotNil(linkerRewrite)
        XCTAssertEqual(linkerRewrite?.count, 2)
    }

    func testIndexPreservesFileIdAcrossMove() async throws {
        let index = harness.loadedVaults[0].index
        let originalFile = index.file(forRelativePath: "Notes/Link Target.md")
        XCTAssertNotNil(originalFile)
        let originalId = originalFile?.id

        _ = try await harness.callTool(
            "move_note",
            arguments: [
                "from_path": .string("Notes/Link Target.md"),
                "to_path": .string("Archived/Link Target.md"),
            ],
            as: Result.self
        )

        // After the move, the file row exists at the new path with the
        // same id — so existing inbound `links.target_file_id` rows
        // continue to point at the right file without re-resolution.
        let movedFile = index.file(forRelativePath: "Archived/Link Target.md")
        XCTAssertNotNil(movedFile)
        XCTAssertEqual(movedFile?.id, originalId)
        XCTAssertNil(index.file(forRelativePath: "Notes/Link Target.md"))
    }

    func testBacklinksContinueToResolveAfterMove() async throws {
        struct Linked: Decodable { let relativePath: String }
        struct BacklinksResult: Decodable {
            let linked: [Linked]
        }

        _ = try await harness.callTool(
            "move_note",
            arguments: [
                "from_path": .string("Notes/Link Target.md"),
                "to_path": .string("Archived/Link Target.md"),
            ],
            as: Result.self
        )

        let backlinks = try await harness.callTool(
            "get_backlinks",
            arguments: ["relative_path": .string("Archived/Link Target.md")],
            as: BacklinksResult.self
        )
        let linkedPaths = Set(backlinks.linked.map(\.relativePath))
        XCTAssertTrue(
            linkedPaths.contains("Notes/Linker.md"),
            "Linker should still appear as an inbound backlink after the rewrite"
        )
    }

    func testDestinationConflictDoesNotRewriteInboundLinks() async throws {
        let index = harness.loadedVaults[0].index
        let linkerURL = harness.vaultURL.appendingPathComponent("Notes/Linker.md")
        let before = try String(contentsOf: linkerURL, encoding: .utf8)

        do {
            _ = try VaultMover.move(
                index: index,
                vaultRootURL: harness.vaultURL,
                oldRelativePath: "Notes/Link Target.md",
                newRelativePath: "Notes/Linker.md"
            )
            XCTFail("expected destination conflict")
        } catch VaultMover.MoveError.destinationExists(let path) {
            XCTAssertEqual(path, "Notes/Linker.md")
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let after = try String(contentsOf: linkerURL, encoding: .utf8)
        XCTAssertEqual(after, before)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: harness.vaultURL.appendingPathComponent("Notes/Link Target.md").path
        ))
    }

    func testSelfLinkIsReindexedAtDestination() async throws {
        let index = harness.loadedVaults[0].index
        let sourcePath = "Notes/Self Link.md"
        let destPath = "Archived/Self Link.md"
        let sourceURL = harness.vaultURL.appendingPathComponent(sourcePath)
        try Data("See [[Self Link]] here.\n".utf8).write(to: sourceURL, options: .atomic)
        _ = try index.updateFile(at: sourcePath)

        let result = try await harness.callTool(
            "move_note",
            arguments: [
                "from_path": .string(sourcePath),
                "to_path": .string(destPath),
            ],
            as: Result.self
        )

        XCTAssertEqual(result.linksRewritten.first?.relativePath, destPath)

        let destURL = harness.vaultURL.appendingPathComponent(destPath)
        let content = try String(contentsOf: destURL, encoding: .utf8)
        XCTAssertTrue(content.contains("[[Archived/Self Link]]"))

        guard let moved = index.file(forRelativePath: destPath) else {
            return XCTFail("moved file missing from index")
        }
        let outgoing = index.linksFrom(fileId: moved.id)
        XCTAssertEqual(outgoing.map(\.targetName), ["Archived/Self Link"])
        XCTAssertEqual(outgoing.first?.targetFileId, moved.id)
    }

    func testMissingSourceErrors() async throws {
        let payload = try await harness.callToolExpectingError(
            "move_note",
            arguments: [
                "from_path": .string("does/not/exist.md"),
                "to_path": .string("anywhere.md"),
            ]
        )
        XCTAssertEqual(payload.error, "note_not_found")
    }

    func testDestinationConflictRejected() async throws {
        // Both fixture files exist, so moving Linker → Link Target.md
        // must conflict.
        let payload = try await harness.callToolExpectingError(
            "move_note",
            arguments: [
                "from_path": .string("Notes/Linker.md"),
                "to_path": .string("Notes/Link Target.md"),
            ]
        )
        XCTAssertEqual(payload.error, "note_exists")
    }

    func testSamePathRejected() async throws {
        let payload = try await harness.callToolExpectingError(
            "move_note",
            arguments: [
                "from_path": .string("Notes/Linker.md"),
                "to_path": .string("Notes/Linker.md"),
            ]
        )
        XCTAssertEqual(payload.error, "invalid_argument")
    }
}
