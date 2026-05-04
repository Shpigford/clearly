import XCTest
@testable import ClearlyCore

final class MarkdownStatsTests: XCTestCase {
    // MARK: - Word counting

    func testCountsPlainProse() {
        let counts = MarkdownStats.compute(text: "Hello world!", selectedRange: NSRange())
        XCTAssertEqual(counts.totalWords, 2)
        XCTAssertEqual(counts.totalChars, "Hello world!".count)
        XCTAssertFalse(counts.hasSelection)
    }

    func testEmptyText() {
        let counts = MarkdownStats.compute(text: "", selectedRange: NSRange())
        XCTAssertEqual(counts.totalWords, 0)
        XCTAssertEqual(counts.totalChars, 0)
        XCTAssertEqual(counts.totalReadingSeconds, 0)
    }

    func testWhitespaceOnlyText() {
        let counts = MarkdownStats.compute(text: "   \n\n  \t", selectedRange: NSRange())
        XCTAssertEqual(counts.totalWords, 0)
    }

    // MARK: - Markdown stripping

    func testStripsBoldAndItalic() {
        let counts = MarkdownStats.compute(text: "**bold** and *italic*", selectedRange: NSRange())
        XCTAssertEqual(counts.totalWords, 3)
        XCTAssertEqual(counts.totalChars, "bold and italic".count)
    }

    func testStripsTripleEmphasis() {
        let counts = MarkdownStats.compute(text: "***hello***", selectedRange: NSRange())
        XCTAssertEqual(counts.totalWords, 1)
        XCTAssertEqual(counts.totalChars, 5)
    }

    func testStripsStrikethroughAndHighlight() {
        let counts = MarkdownStats.compute(text: "~~gone~~ ==kept==", selectedRange: NSRange())
        XCTAssertEqual(counts.totalWords, 2)
        XCTAssertEqual(counts.totalChars, "gone kept".count)
    }

    func testStripsAtxHeading() {
        let counts = MarkdownStats.compute(text: "## Heading text", selectedRange: NSRange())
        XCTAssertEqual(counts.totalWords, 2)
        XCTAssertEqual(counts.totalChars, "Heading text".count)
    }

    func testStripsBlockquoteAndList() {
        let text = """
        > quoted thought
        - first
        - second
        1. ordered
        """
        let counts = MarkdownStats.compute(text: text, selectedRange: NSRange())
        XCTAssertEqual(counts.totalWords, 5)
    }

    func testStripsTaskListMarkers() {
        let text = "- [ ] todo one\n- [x] done two"
        let counts = MarkdownStats.compute(text: text, selectedRange: NSRange())
        XCTAssertEqual(counts.totalWords, 4)
    }

    func testKeepsLinkLabelDropsURL() {
        let counts = MarkdownStats.compute(
            text: "Click [the docs](https://example.com/path/to/page).",
            selectedRange: NSRange()
        )
        XCTAssertEqual(counts.totalWords, 3)
        XCTAssertEqual(counts.totalChars, "Click the docs.".count)
    }

    func testDropsImageEntirely() {
        let counts = MarkdownStats.compute(
            text: "before ![alt text](image.png) after",
            selectedRange: NSRange()
        )
        XCTAssertEqual(counts.totalWords, 2)
    }

    func testWikiLinkPlainAndAlias() {
        let plain = MarkdownStats.compute(text: "see [[Page]]", selectedRange: NSRange())
        XCTAssertEqual(plain.totalWords, 2)
        XCTAssertEqual(plain.totalChars, "see Page".count)

        let aliased = MarkdownStats.compute(text: "see [[Page|other name]]", selectedRange: NSRange())
        XCTAssertEqual(aliased.totalWords, 3)
        XCTAssertEqual(aliased.totalChars, "see other name".count)
    }

    func testStripsFencedCodeKeepsContent() {
        let text = """
        intro
        ```swift
        let x = 1
        ```
        outro
        """
        let counts = MarkdownStats.compute(text: text, selectedRange: NSRange())
        XCTAssertEqual(counts.totalWords, 5)
    }

    func testStripsInlineCode() {
        let counts = MarkdownStats.compute(text: "use `let x = 1` here", selectedRange: NSRange())
        XCTAssertEqual(counts.totalWords, 5)
    }

    func testStripsFrontmatter() {
        let text = """
        ---
        title: Hello
        author: Josh
        ---
        body words here
        """
        let counts = MarkdownStats.compute(text: text, selectedRange: NSRange())
        XCTAssertEqual(counts.totalWords, 3)
    }

    func testStripsHTMLTags() {
        let counts = MarkdownStats.compute(
            text: "<p>html <strong>chunk</strong> here</p>",
            selectedRange: NSRange()
        )
        XCTAssertEqual(counts.totalWords, 3)
    }

    // MARK: - Grapheme correctness

    func testEmojiCountsAsSingleCharacter() {
        let counts = MarkdownStats.compute(text: "👨‍👩‍👧", selectedRange: NSRange())
        XCTAssertEqual(counts.totalChars, 1)
    }

    func testFlagEmojiCountsAsSingleCharacter() {
        let counts = MarkdownStats.compute(text: "🇺🇸", selectedRange: NSRange())
        XCTAssertEqual(counts.totalChars, 1)
    }

    // MARK: - Reading time

    func testReadingTimeUnderThirtySeconds() {
        let text = String(repeating: "word ", count: 50) // 50 words → 50/265*60 ≈ 11s
        let counts = MarkdownStats.compute(text: text, selectedRange: NSRange())
        XCTAssertLessThan(counts.totalReadingSeconds, 30)
    }

    func testReadingTimeRoundsUp() {
        let text = String(repeating: "word ", count: 266) // 266/265*60 ≈ 60.2s → 61s
        let counts = MarkdownStats.compute(text: text, selectedRange: NSRange())
        XCTAssertGreaterThan(counts.totalReadingSeconds, 60)
    }

    // MARK: - Selection

    func testSelectionCountsSubsetOfTotals() {
        let text = "Hello world from Clearly"
        let nsText = text as NSString
        let range = nsText.range(of: "world from")
        let counts = MarkdownStats.compute(text: text, selectedRange: range)
        XCTAssertTrue(counts.hasSelection)
        XCTAssertEqual(counts.selectionWords, 2)
        XCTAssertEqual(counts.selectionChars, "world from".count)
        XCTAssertEqual(counts.totalWords, 4)
    }

    func testSelectionRespectsMarkdownStripping() {
        let text = "**Hello world**"
        let range = NSRange(location: 0, length: (text as NSString).length)
        let counts = MarkdownStats.compute(text: text, selectedRange: range)
        XCTAssertEqual(counts.selectionWords, 2)
        XCTAssertEqual(counts.selectionChars, "Hello world".count)
    }

    func testZeroLengthSelectionIsNotCounted() {
        let counts = MarkdownStats.compute(
            text: "Hello",
            selectedRange: NSRange(location: 2, length: 0)
        )
        XCTAssertFalse(counts.hasSelection)
    }

    func testOutOfBoundsSelectionIsIgnored() {
        let counts = MarkdownStats.compute(
            text: "abc",
            selectedRange: NSRange(location: 0, length: 99)
        )
        XCTAssertFalse(counts.hasSelection)
    }
}
