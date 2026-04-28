import XCTest
@testable import ClearlyCore

final class WikiIntegrationCandidatesTests: XCTestCase {

    // MARK: - select(allPaths:indexContent:)

    func testReturnsNotesNotReferencedInIndex() {
        let paths = ["concepts/foo.md", "people/jane.md"]
        let index = """
        # Index

        ## Concepts
        - [[foo]]
        """
        let result = WikiIntegrationCandidates.select(allPaths: paths, indexContent: index)
        XCTAssertEqual(result, ["people/jane.md"])
    }

    func testFiltersOutSystemFiles() {
        let paths = [
            "index.md",
            "log.md",
            "AGENTS.md",
            "getting-started.md",
            "raw/article.md",
            "_audit/2026-04.md",
            ".clearly/state.json",
            "concepts/foo.md",
        ]
        let result = WikiIntegrationCandidates.select(allPaths: paths, indexContent: "")
        XCTAssertEqual(result, ["concepts/foo.md"])
    }

    func testMatchesByVaultRelativeStem() {
        let paths = ["concepts/foo.md", "people/foo.md"]
        let index = "[[concepts/foo]]"
        // Only concepts/foo is indexed; people/foo is a different note with
        // the same basename. Path-anchored match keeps people/foo as a
        // candidate.
        let result = WikiIntegrationCandidates.select(allPaths: paths, indexContent: index)
        XCTAssertEqual(result, ["people/foo.md"])
    }

    func testMatchesByBasenameStem() {
        let paths = ["concepts/foo.md"]
        // User wrote `[[foo]]` (just the basename) — should still count as
        // indexed because that's how Obsidian-style links typically work.
        let index = "[[foo]]"
        XCTAssertEqual(WikiIntegrationCandidates.select(allPaths: paths, indexContent: index), [])
    }

    func testDoesNotMatchDuplicateBasenamesByBareStem() {
        let paths = ["concepts/foo.md", "people/foo.md"]
        let index = "[[foo]]"
        XCTAssertEqual(WikiIntegrationCandidates.select(allPaths: paths, indexContent: index), [
            "concepts/foo.md",
            "people/foo.md",
        ])
    }

    func testMatchingIsCaseInsensitive() {
        let paths = ["concepts/Foo.md"]
        let index = "[[foo]]"
        XCTAssertEqual(WikiIntegrationCandidates.select(allPaths: paths, indexContent: index), [])
    }

    func testStripsAliasAndAnchorWhenMatching() {
        let paths = ["concepts/foo.md", "people/jane.md"]
        let index = """
        - [[foo|Foo Page]]
        - [[jane#Background]]
        """
        let result = WikiIntegrationCandidates.select(allPaths: paths, indexContent: index)
        XCTAssertEqual(result, [])
    }

    func testReturnsResultsSorted() {
        let paths = ["zebra.md", "alpha.md", "mango.md"]
        let result = WikiIntegrationCandidates.select(allPaths: paths, indexContent: "")
        XCTAssertEqual(result, ["alpha.md", "mango.md", "zebra.md"])
    }

    func testEmptyVaultReturnsEmpty() {
        XCTAssertEqual(WikiIntegrationCandidates.select(allPaths: [], indexContent: ""), [])
    }

    func testFullyIndexedVaultReturnsEmpty() {
        let paths = ["concepts/foo.md", "people/jane.md"]
        let index = "[[foo]] [[jane]]"
        XCTAssertEqual(WikiIntegrationCandidates.select(allPaths: paths, indexContent: index), [])
    }

    // MARK: - indexedReferences(in:)

    func testExtractsLinksWithoutAliasOrAnchor() {
        let index = """
        # Index
        - [[plain]]
        - [[with-alias|Display Text]]
        - [[with-anchor#Section]]
        - [[both|Display]]#NotPart
        """
        let refs = WikiIntegrationCandidates.indexedReferences(in: index)
        XCTAssertTrue(refs.contains("plain"))
        XCTAssertTrue(refs.contains("with-alias"))
        XCTAssertTrue(refs.contains("with-anchor"))
        XCTAssertTrue(refs.contains("both"))
    }

    func testIgnoresEmptyLinkBodies() {
        let index = "[[]] [[real]]"
        let refs = WikiIntegrationCandidates.indexedReferences(in: index)
        XCTAssertEqual(refs, ["real"])
    }

    func testEmptyIndexReturnsEmptySet() {
        XCTAssertEqual(WikiIntegrationCandidates.indexedReferences(in: ""), [])
    }
}
