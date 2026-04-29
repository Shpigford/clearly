import Foundation
import ClearlyCore
import MCP
import XCTest

/// End-to-end coverage of the `tag:` and `path:` operators introduced by
/// `SearchQueryParser` and the JOIN-based filtering in
/// `VaultIndex.searchFilesGrouped(parsed:)`. Drives the same MCP
/// `search_notes` tool the live server exposes — operators are pulled
/// from the query string, no schema change.
final class SearchOperatorTests: XCTestCase {
    var harness: TestVaultHarness!

    override func setUp() async throws {
        harness = try await TestVaultHarness()
    }

    override func tearDown() async throws {
        await harness?.tearDown()
        harness = nil
    }

    private struct SearchHit: Decodable {
        let relativePath: String
    }
    private struct SearchResult: Decodable {
        let totalCount: Int
        let returnedCount: Int
        let results: [SearchHit]
    }

    // FixtureVault tags (frontmatter + inline #hashtags):
    //   README.md            tags: fixture, meta
    //   Daily/2026-04-17.md  tags: daily, fixture
    //   Projects/Plan.md     tags: architecture, planning
    //   Notes/Link Target.md inline #architecture
    //   Notes/Linker.md      inline #fixture
    //   Resume-é.md          inline #resume

    func testTagFilterAloneReturnsEveryFileCarryingTheTag() async throws {
        let result = try await harness.callTool(
            "search_notes",
            arguments: ["query": .string("tag:fixture")],
            as: SearchResult.self
        )
        let paths = Set(result.results.map(\.relativePath))
        XCTAssertEqual(paths, Set([
            "README.md",
            "Daily/2026-04-17.md",
            "Notes/Linker.md",
        ]))
    }

    func testTagFiltersAreAndCombined() async throws {
        let result = try await harness.callTool(
            "search_notes",
            arguments: ["query": .string("tag:fixture tag:meta")],
            as: SearchResult.self
        )
        XCTAssertEqual(result.results.map(\.relativePath), ["README.md"])
    }

    func testTagFilterIsCaseInsensitive() async throws {
        let result = try await harness.callTool(
            "search_notes",
            arguments: ["query": .string("tag:FIXTURE")],
            as: SearchResult.self
        )
        let paths = Set(result.results.map(\.relativePath))
        XCTAssertTrue(paths.contains("README.md"))
        XCTAssertTrue(paths.contains("Daily/2026-04-17.md"))
        XCTAssertTrue(paths.contains("Notes/Linker.md"))
    }

    func testPathPrefixNarrowsToSubfolder() async throws {
        let result = try await harness.callTool(
            "search_notes",
            arguments: ["query": .string("path:Daily/")],
            as: SearchResult.self
        )
        XCTAssertEqual(result.results.map(\.relativePath), ["Daily/2026-04-17.md"])
    }

    func testTagAndPathCombineToIntersection() async throws {
        let result = try await harness.callTool(
            "search_notes",
            arguments: ["query": .string("path:Notes/ tag:fixture")],
            as: SearchResult.self
        )
        XCTAssertEqual(result.results.map(\.relativePath), ["Notes/Linker.md"])
    }

    func testFilterPlusFreeTextLimitsToBothConstraints() async throws {
        // "Linker" is in Notes/Linker.md's content; only one fixture-tagged
        // file mentions it.
        let result = try await harness.callTool(
            "search_notes",
            arguments: ["query": .string("tag:fixture Linker")],
            as: SearchResult.self
        )
        XCTAssertEqual(result.results.map(\.relativePath), ["Notes/Linker.md"])
    }

    func testUnknownOperatorDoesNotFilter() async throws {
        // `foo:bar` is not a recognized operator; it's a literal FTS term
        // that doesn't appear anywhere in the fixture vault.
        let result = try await harness.callTool(
            "search_notes",
            arguments: ["query": .string("foo:bar Linker")],
            as: SearchResult.self
        )
        // Should return Notes/Linker.md from the "Linker" term — not
        // filtered out by foo:bar.
        XCTAssertTrue(result.results.contains { $0.relativePath == "Notes/Linker.md" })
    }
}
