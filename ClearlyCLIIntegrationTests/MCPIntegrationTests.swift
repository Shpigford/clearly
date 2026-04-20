import Foundation
import ClearlyCore
import MCP
import XCTest

/// End-to-end test of the 9 MCP tools exposed by ClearlyCLI, driving a real
/// Server over InMemoryTransport with a real Client. Each test exercises the
/// success path; ErrorPathTests covers ToolError cases.
final class MCPIntegrationTests: XCTestCase {
    var harness: TestVaultHarness!

    override func setUp() async throws {
        harness = try await TestVaultHarness()
    }

    override func tearDown() async throws {
        await harness?.tearDown()
        harness = nil
    }

    // MARK: - tools/list

    func testListToolsReturnsNine() async throws {
        let (tools, _) = try await harness.client.listTools()
        XCTAssertEqual(tools.count, 9)
        let names = Set(tools.map(\.name))
        XCTAssertEqual(names, Set([
            "search_notes", "get_backlinks", "get_tags",
            "read_note", "list_notes", "get_headings",
            "get_frontmatter", "create_note", "update_note"
        ]))
        // Every tool advertises an outputSchema.
        for t in tools {
            XCTAssertNotNil(t.outputSchema, "\(t.name) missing outputSchema")
            XCTAssertNotNil(t.annotations, "\(t.name) missing annotations")
        }
    }

    // MARK: - search_notes

    func testSearchNotesReturnsHits() async throws {
        struct Hit: Decodable {
            let relativePath: String
            let filename: String
            let vault: String
            let matchesFilename: Bool
        }
        struct Result: Decodable { let results: [Hit]; let totalCount: Int }
        let result = try await harness.callTool(
            "search_notes",
            arguments: ["query": .string("Link Target"), "limit": .int(10)],
            as: Result.self
        )
        XCTAssertGreaterThan(result.totalCount, 0)
        XCTAssertTrue(
            result.results.contains { $0.relativePath.contains("Link Target") },
            "expected a hit touching 'Link Target'"
        )
    }

    // MARK: - read_note

    func testReadNoteReturnsContentAndHash() async throws {
        struct Result: Decodable {
            let content: String
            let contentHash: String
            let sizeBytes: Int
            let vault: String
            let relativePath: String
        }
        let result = try await harness.callTool(
            "read_note",
            arguments: ["relative_path": .string("Daily/2026-04-17.md")],
            as: Result.self
        )
        XCTAssertTrue(result.content.contains("# 2026-04-17"))
        XCTAssertEqual(result.contentHash.count, 64) // SHA-256 hex
        XCTAssertGreaterThan(result.sizeBytes, 0)
    }

    func testReadNoteLineRangeClampsContent() async throws {
        struct Range: Decodable { let start: Int; let end: Int }
        struct Result: Decodable { let content: String; let lineRange: Range? }
        let result = try await harness.callTool(
            "read_note",
            arguments: [
                "relative_path": .string("Daily/2026-04-17.md"),
                "start_line": .int(1),
                "end_line": .int(2)
            ],
            as: Result.self
        )
        XCTAssertNotNil(result.lineRange)
        XCTAssertEqual(result.lineRange?.start, 1)
        XCTAssertEqual(result.lineRange?.end, 2)
        XCTAssertLessThanOrEqual(
            result.content.components(separatedBy: "\n").count,
            3  // up to 2 lines + potential trailing newline
        )
    }

    // MARK: - list_notes

    func testListNotesReturnsFixtureCount() async throws {
        struct Note: Decodable { let relativePath: String }
        struct Result: Decodable { let notes: [Note] }
        let result = try await harness.callTool(
            "list_notes",
            arguments: [:],
            as: Result.self
        )
        // FixtureVault has 7 markdown files.
        XCTAssertEqual(result.notes.count, 7, "unexpected fixture size: \(result.notes.map(\.relativePath))")
    }

    func testListNotesFiltersByUnder() async throws {
        struct Note: Decodable { let relativePath: String }
        struct Result: Decodable { let notes: [Note] }
        let result = try await harness.callTool(
            "list_notes",
            arguments: ["under": .string("Notes/")],
            as: Result.self
        )
        XCTAssertEqual(result.notes.count, 3)
        XCTAssertTrue(result.notes.allSatisfy { $0.relativePath.hasPrefix("Notes/") })
    }

    // MARK: - get_headings

    func testGetHeadingsReturnsOutline() async throws {
        struct Heading: Decodable { let level: Int; let text: String; let lineNumber: Int }
        struct Result: Decodable { let headings: [Heading] }
        let result = try await harness.callTool(
            "get_headings",
            arguments: ["relative_path": .string("Daily/2026-04-17.md")],
            as: Result.self
        )
        XCTAssertFalse(result.headings.isEmpty)
        XCTAssertTrue(result.headings.contains { $0.level == 1 && $0.text == "2026-04-17" })
        XCTAssertTrue(result.headings.contains { $0.level == 3 && $0.text == "Deep work" })
    }

    // MARK: - get_frontmatter

    func testGetFrontmatterFlatMap() async throws {
        struct Result: Decodable { let hasFrontmatter: Bool; let frontmatter: [String: String] }
        let result = try await harness.callTool(
            "get_frontmatter",
            arguments: ["relative_path": .string("Projects/Plan.md")],
            as: Result.self
        )
        XCTAssertTrue(result.hasFrontmatter)
        XCTAssertEqual(result.frontmatter["title"], "Project Plan")
        XCTAssertEqual(result.frontmatter["status"], "active")
    }

    func testGetFrontmatterAbsent() async throws {
        struct Result: Decodable { let hasFrontmatter: Bool; let frontmatter: [String: String] }
        let result = try await harness.callTool(
            "get_frontmatter",
            arguments: ["relative_path": .string("Notes/Link Target.md")],
            as: Result.self
        )
        XCTAssertFalse(result.hasFrontmatter)
        XCTAssertTrue(result.frontmatter.isEmpty)
    }

    // MARK: - get_backlinks

    func testGetBacklinksSeparatesLinkedAndUnlinked() async throws {
        struct LinkedEntry: Decodable { let relativePath: String }
        struct UnlinkedEntry: Decodable { let relativePath: String }
        struct Result: Decodable {
            let linked: [LinkedEntry]
            let unlinked: [UnlinkedEntry]
            let relativePath: String
            let vault: String
        }
        let result = try await harness.callTool(
            "get_backlinks",
            arguments: ["relative_path": .string("Notes/Link Target.md")],
            as: Result.self
        )
        // Linker.md has two [[Link Target]] references; Plan.md has one.
        XCTAssertGreaterThanOrEqual(result.linked.count, 3)
        XCTAssertTrue(result.linked.contains { $0.relativePath == "Notes/Linker.md" })
        XCTAssertTrue(result.linked.contains { $0.relativePath == "Projects/Plan.md" })
        // Unlinked Mention.md references the target in plain text.
        XCTAssertTrue(result.unlinked.contains { $0.relativePath == "Notes/Unlinked Mention.md" })
    }

    // MARK: - get_tags

    func testGetTagsAllMode() async throws {
        struct TagCount: Decodable { let tag: String; let count: Int }
        struct Result: Decodable { let mode: String; let allTags: [TagCount]? }
        let result = try await harness.callTool(
            "get_tags",
            arguments: [:],
            as: Result.self
        )
        XCTAssertEqual(result.mode, "all")
        XCTAssertNotNil(result.allTags)
        XCTAssertTrue(result.allTags!.contains { $0.tag == "fixture" })
        XCTAssertTrue(result.allTags!.contains { $0.tag == "architecture" })
    }

    func testGetTagsByTagMode() async throws {
        struct FileEntry: Decodable { let relativePath: String; let vault: String }
        struct Result: Decodable { let mode: String; let files: [FileEntry]? }
        let result = try await harness.callTool(
            "get_tags",
            arguments: ["tag": .string("architecture")],
            as: Result.self
        )
        XCTAssertEqual(result.mode, "by_tag")
        XCTAssertNotNil(result.files)
        XCTAssertTrue(result.files!.contains { $0.relativePath == "Projects/Plan.md" })
    }

    // MARK: - create_note + update_note

    func testCreateNoteAndReadBack() async throws {
        struct CreateResult: Decodable {
            let vault: String
            let relativePath: String
            let contentHash: String
            let sizeBytes: Int
        }
        let create = try await harness.callTool(
            "create_note",
            arguments: [
                "relative_path": .string("Inbox/new-note.md"),
                "content": .string("# Fresh Note\n\nBody text.\n")
            ],
            as: CreateResult.self
        )
        XCTAssertEqual(create.relativePath, "Inbox/new-note.md")
        XCTAssertEqual(create.contentHash.count, 64)  // SHA-256 hex
        XCTAssertGreaterThan(create.sizeBytes, 0)

        // Read it back
        struct ReadResult: Decodable { let content: String }
        let read = try await harness.callTool(
            "read_note",
            arguments: ["relative_path": .string("Inbox/new-note.md")],
            as: ReadResult.self
        )
        XCTAssertTrue(read.content.contains("# Fresh Note"))
    }

    func testUpdateNoteAppend() async throws {
        struct Ignored: Decodable {}
        _ = try await harness.callTool(
            "create_note",
            arguments: [
                "relative_path": .string("Inbox/appendable.md"),
                "content": .string("Line 1\n")
            ],
            as: Ignored.self
        )
        _ = try await harness.callTool(
            "update_note",
            arguments: [
                "relative_path": .string("Inbox/appendable.md"),
                "mode": .string("append"),
                "content": .string("Line 2\n")
            ],
            as: Ignored.self
        )
        struct ReadResult: Decodable { let content: String }
        let read = try await harness.callTool(
            "read_note",
            arguments: ["relative_path": .string("Inbox/appendable.md")],
            as: ReadResult.self
        )
        XCTAssertTrue(read.content.contains("Line 1"))
        XCTAssertTrue(read.content.contains("Line 2"))
    }

    func testUpdateNotePrependPreservesFrontmatter() async throws {
        struct Ignored: Decodable {}
        _ = try await harness.callTool(
            "create_note",
            arguments: [
                "relative_path": .string("Inbox/fm.md"),
                "content": .string("---\ntitle: FM\n---\n\nBody.\n")
            ],
            as: Ignored.self
        )
        _ = try await harness.callTool(
            "update_note",
            arguments: [
                "relative_path": .string("Inbox/fm.md"),
                "mode": .string("prepend"),
                "content": .string("## Top Heading\n\n")
            ],
            as: Ignored.self
        )
        struct ReadResult: Decodable { let content: String }
        let read = try await harness.callTool(
            "read_note",
            arguments: ["relative_path": .string("Inbox/fm.md")],
            as: ReadResult.self
        )
        // frontmatter stays first; inserted content lands after the closing ---
        let parts = read.content.components(separatedBy: "---\n")
        XCTAssertGreaterThanOrEqual(parts.count, 3)
        XCTAssertTrue(parts.last!.contains("## Top Heading"))
        XCTAssertTrue(parts.last!.contains("Body."))
    }
}
