import XCTest
@testable import ClearlyCore

final class MarkdownChunkerTests: XCTestCase {

    // MARK: - Empty / degenerate inputs

    func testEmptySourceReturnsNoChunks() {
        XCTAssertEqual(MarkdownChunker.chunk(source: "", filename: "any.md"), [])
    }

    func testFrontmatterOnlyReturnsNoChunks() {
        let source = """
        ---
        title: Empty
        ---
        """
        XCTAssertEqual(MarkdownChunker.chunk(source: source, filename: "empty.md"), [])
    }

    func testWhitespaceOnlyBodyReturnsNoChunks() {
        let source = "   \n\n   \n"
        XCTAssertEqual(MarkdownChunker.chunk(source: source, filename: "blank.md"), [])
    }

    // MARK: - Single-chunk paths

    func testTinyNoteEmitsSingleChunk() {
        let source = "# Hello\n\nThis is a tiny note."
        let chunks = MarkdownChunker.chunk(source: source, filename: "hello.md")
        XCTAssertEqual(chunks.count, 1)
        let chunk = chunks[0]
        XCTAssertEqual(chunk.index, 0)
        XCTAssertEqual(chunk.headingPath, ["Hello"])
        XCTAssertEqual(chunk.body, "This is a tiny note.")
        XCTAssertEqual(chunk.embedText, "hello > Hello: This is a tiny note.")
    }

    func testNoHeadingsTreatsBodyAsOneChunk() {
        let source = "Just a paragraph with no structure at all."
        let chunks = MarkdownChunker.chunk(source: source, filename: "flat.md")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].headingPath, [])
        XCTAssertEqual(chunks[0].body, source)
        XCTAssertEqual(chunks[0].embedText, "flat: Just a paragraph with no structure at all.")
    }

    // MARK: - Heading-based splits

    func testH1AndH2SplitsIntoSections() {
        let source = """
        # Top

        Top body.

        ## Sub A

        Sub A body.

        ## Sub B

        Sub B body.
        """
        let chunks = MarkdownChunker.chunk(source: source, filename: "doc.md")
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].headingPath, ["Top"])
        XCTAssertEqual(chunks[0].body.trimmingCharacters(in: .whitespacesAndNewlines), "Top body.")
        XCTAssertEqual(chunks[1].headingPath, ["Top", "Sub A"])
        XCTAssertEqual(chunks[1].body.trimmingCharacters(in: .whitespacesAndNewlines), "Sub A body.")
        XCTAssertEqual(chunks[2].headingPath, ["Top", "Sub B"])
        XCTAssertEqual(chunks[2].body.trimmingCharacters(in: .whitespacesAndNewlines), "Sub B body.")
    }

    func testH2WithoutH1StartsNewSection() {
        let source = """
        ## Lone

        Body for lone.
        """
        let chunks = MarkdownChunker.chunk(source: source, filename: "lone.md")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].headingPath, ["Lone"])
    }

    func testH4AndDeeperLiveInsideParentSection() {
        let source = """
        # Top

        Top intro.

        #### Aside

        Aside body should not split.

        More top text.
        """
        let chunks = MarkdownChunker.chunk(source: source, filename: "deep.md")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].headingPath, ["Top"])
        XCTAssertTrue(chunks[0].body.contains("Aside body"))
        XCTAssertTrue(chunks[0].body.contains("More top text"))
    }

    func testEmptySectionsAreDropped() {
        // Two H2s with nothing between them: only the second's body should produce a chunk.
        let source = """
        ## Empty
        ## Filled

        Filled body.
        """
        let chunks = MarkdownChunker.chunk(source: source, filename: "skip.md")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].headingPath, ["Filled"])
    }

    // MARK: - Code fences shouldn't trigger splits

    func testHeadingInsideCodeFenceDoesNotSplit() {
        let source = """
        # Real heading

        Real body.

        ```
        # not a heading
        ## also not a heading
        ```

        Trailing text.
        """
        let chunks = MarkdownChunker.chunk(source: source, filename: "code.md")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].headingPath, ["Real heading"])
        XCTAssertTrue(chunks[0].body.contains("# not a heading"))
        XCTAssertTrue(chunks[0].body.contains("Trailing text"))
    }

    func testTildeFenceAlsoOpaque() {
        let source = """
        # Top

        Body.

        ~~~
        ## fake heading
        ~~~

        After.
        """
        let chunks = MarkdownChunker.chunk(source: source, filename: "tilde.md")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].headingPath, ["Top"])
    }

    // MARK: - Frontmatter title takes precedence

    func testFrontmatterTitleOverridesFilenameInPrefix() {
        let source = """
        ---
        title: Local-First Software
        tags: [research]
        ---

        # Heading

        Body.
        """
        let chunks = MarkdownChunker.chunk(source: source, filename: "lfs.md")
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].embedText, "Local-First Software > Heading: Body.")
    }

    func testFilenameStripsExtensionInPrefix() {
        let source = "# T\n\nBody."
        let chunks = MarkdownChunker.chunk(source: source, filename: "Some Note.md")
        XCTAssertEqual(chunks[0].embedText, "Some Note > T: Body.")
    }

    // MARK: - Sliding-window fallback for oversized sections

    func testOversizedSectionSlidesIntoMultipleChunks() {
        // 600 short tokens forces the 256-target window to fire at least 3 times.
        let words = (0..<600).map { "word\($0)" }.joined(separator: " ")
        let source = "# Big\n\n\(words)"
        let chunks = MarkdownChunker.chunk(source: source, filename: "big.md", targetTokens: 256, overlapTokens: 40)
        XCTAssertGreaterThanOrEqual(chunks.count, 3)
        for chunk in chunks {
            XCTAssertEqual(chunk.headingPath, ["Big"])
            XCTAssertTrue(chunk.embedText.hasPrefix("big > Big: "))
        }
        // Indices stay monotonic.
        XCTAssertEqual(chunks.map(\.index), Array(0..<chunks.count))
    }

    func testSlidingWindowOverlapPreservesContext() {
        let words = (0..<600).map { "word\($0)" }.joined(separator: " ")
        let source = "# X\n\n\(words)"
        let chunks = MarkdownChunker.chunk(source: source, filename: "x.md", targetTokens: 100, overlapTokens: 30)
        // Each chunk after the first should share ~30 words of overlap with the prior chunk
        // (target=100, overlap=30 ⇒ stride=70). Compare full token sets between consecutive
        // chunks rather than fixed-byte tail/head slices, since "30 words" doesn't map to a
        // tidy character count in either body.
        for i in 1..<chunks.count {
            let priorTokens = Set(chunks[i - 1].body.split { $0.isWhitespace || $0.isNewline }.map(String.init))
            let currentTokens = Set(chunks[i].body.split { $0.isWhitespace || $0.isNewline }.map(String.init))
            let intersection = priorTokens.intersection(currentTokens)
            XCTAssertGreaterThanOrEqual(intersection.count, 20,
                                        "Expected at least 20 shared tokens between chunk \(i-1) and \(i); got \(intersection.count)")
        }
    }

    // MARK: - Byte offsets land where expected

    func testTextOffsetPointsToBodyInOriginalSource() {
        let source = """
        ---
        title: T
        ---

        # H

        Body.
        """
        let chunks = MarkdownChunker.chunk(source: source, filename: "x.md")
        XCTAssertEqual(chunks.count, 1)
        let offset = chunks[0].textOffset
        let length = chunks[0].textLength
        let bytes = Array(source.utf8)
        let slice = bytes[offset..<(offset + length)]
        let recovered = String(decoding: slice, as: UTF8.self)
        XCTAssertEqual(recovered, "Body.")
    }
}
