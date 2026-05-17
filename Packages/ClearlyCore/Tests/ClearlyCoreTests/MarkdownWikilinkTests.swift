import XCTest
@testable import ClearlyCore

final class MarkdownWikilinkTests: XCTestCase {
    // MARK: - Basic rendering

    func testPlainWikilink() {
        let html = MarkdownRenderer.renderHTML("See [[Marcus Aurelius]] for more.")
        let expected = "<a class=\"wiki-link\" href=\"#\" data-wiki-target=\"Marcus Aurelius\">Marcus Aurelius</a>"
        XCTAssertTrue(html.contains(expected), html)
    }

    func testWikilinkWithAlias() {
        let html = MarkdownRenderer.renderHTML("[[Marcus Aurelius Antoninus|Marcus Aurelius]]")
        XCTAssertTrue(html.contains(#"data-wiki-target="Marcus Aurelius Antoninus""#), html)
        XCTAssertTrue(html.contains(#"data-wiki-alias="Marcus Aurelius""#), html)
        XCTAssertTrue(html.contains(">Marcus Aurelius</a>"), html)
        XCTAssertFalse(html.contains("[[Marcus"), "raw wikilink text leaked through: \(html)")
    }

    func testWikilinkWithHeading() {
        let html = MarkdownRenderer.renderHTML("[[Page#Section]]")
        XCTAssertTrue(html.contains(#"data-wiki-target="Page""#), html)
        XCTAssertTrue(html.contains(#"data-wiki-heading="Section""#), html)
        XCTAssertTrue(html.contains(">Page#Section</a>"), html)
    }

    func testWikilinkWithHeadingAndAlias() {
        let html = MarkdownRenderer.renderHTML("[[Page#Section|Alias]]")
        XCTAssertTrue(html.contains(#"data-wiki-target="Page""#), html)
        XCTAssertTrue(html.contains(#"data-wiki-heading="Section""#), html)
        XCTAssertTrue(html.contains(#"data-wiki-alias="Alias""#), html)
        XCTAssertTrue(html.contains(">Alias</a>"), html)
    }

    func testEscapedPipeFormRenders() {
        // Obsidian convention: \| as alias separator.
        let html = MarkdownRenderer.renderHTML(#"[[Page\|Alias]]"#)
        XCTAssertTrue(html.contains(#"data-wiki-target="Page""#), html)
        XCTAssertTrue(html.contains(#"data-wiki-alias="Alias""#), html)
        XCTAssertTrue(html.contains(">Alias</a>"), html)
    }

    // MARK: - Issue #371: tables

    func testWikilinkInsideTableCellDoesNotSplitRow() {
        let md = """
        | Quote | Author | Movement |
        | - | - | - |
        | A quote. | [[Marcus Aurelius Antoninus|Marcus Aurelius]] | [[Stoicism]] |
        """
        let html = MarkdownRenderer.renderHTML(md)
        // Two wikilinks rendered.
        XCTAssertTrue(html.contains(#"data-wiki-target="Marcus Aurelius Antoninus""#), html)
        XCTAssertTrue(html.contains(#"data-wiki-target="Stoicism""#), html)
        // Header row defined three columns; data row should also have three <td>.
        let tdCount = html.components(separatedBy: "<td").count - 1
        XCTAssertEqual(tdCount, 3, "expected exactly 3 <td> cells in the data row; html=\(html)")
        // No leaked literal wikilink fragments.
        XCTAssertFalse(html.contains("[[Marcus"), html)
        XCTAssertFalse(html.contains("Aurelius]]"), html)
    }

    func testEscapedPipeInsideTableCellRenders() {
        let md = """
        | Author |
        | - |
        | [[Marcus Aurelius Antoninus\\|Marcus Aurelius]] |
        """
        let html = MarkdownRenderer.renderHTML(md)
        XCTAssertTrue(html.contains(#"data-wiki-alias="Marcus Aurelius""#), html)
        XCTAssertTrue(html.contains(">Marcus Aurelius</a>"), html)
    }

    // MARK: - Code skipping

    func testWikilinkInsideFencedCodeStaysLiteral() {
        let md = """
        ```
        [[Page|Alias]]
        ```
        """
        let html = MarkdownRenderer.renderHTML(md)
        XCTAssertFalse(html.contains("wiki-link"), html)
        XCTAssertTrue(html.contains("[[Page|Alias]]"), html)
    }

    func testWikilinkInsideInlineCodeStaysLiteral() {
        let html = MarkdownRenderer.renderHTML("Type `[[Page|Alias]]` to link.")
        XCTAssertFalse(html.contains("wiki-link"), html)
        XCTAssertTrue(html.contains("[[Page|Alias]]"), html)
    }

    func testWikilinkOutsideInlineCodeStillRenders() {
        let html = MarkdownRenderer.renderHTML("`code` and then [[RealLink|Click]].")
        XCTAssertTrue(html.contains(#"data-wiki-target="RealLink""#), html)
    }

    // MARK: - Edge cases

    func testTextPipeOutsideWikilinkIsUntouched() {
        let html = MarkdownRenderer.renderHTML("a | b | c")
        XCTAssertFalse(html.contains("wiki-link"), html)
        XCTAssertTrue(html.contains("a | b | c"), html)
    }

    func testUnclosedWikilinkLeftAlone() {
        // No matching ]] anywhere on the line.
        let html = MarkdownRenderer.renderHTML("Type [[ to begin a link.")
        XCTAssertFalse(html.contains("wiki-link"), html)
    }

    func testWikilinkDoesNotSpanLines() {
        let md = "First line has [[an unclosed\nopener and second line has it ]] closed."
        let html = MarkdownRenderer.renderHTML(md)
        XCTAssertFalse(html.contains("wiki-link"), html)
    }

    func testMultipleWikilinksInOneParagraph() {
        let html = MarkdownRenderer.renderHTML("[[A]] and [[B|bee]] and [[C#H]].")
        XCTAssertTrue(html.contains(#"data-wiki-target="A""#), html)
        XCTAssertTrue(html.contains(#"data-wiki-target="B""#), html)
        XCTAssertTrue(html.contains(#"data-wiki-target="C""#), html)
        XCTAssertTrue(html.contains(#"data-wiki-alias="bee""#), html)
        XCTAssertTrue(html.contains(#"data-wiki-heading="H""#), html)
    }

    func testQuoteInTargetIsEscapedInAttribute() {
        let html = MarkdownRenderer.renderHTML(#"[[Say "Hi"|wave]]"#)
        XCTAssertTrue(html.contains(#"data-wiki-target="Say &quot;Hi&quot;""#), html)
        XCTAssertTrue(html.contains(">wave</a>"), html)
    }

    func testWikilinkInsideHeadingProducesTOCLink() {
        let md = """
        [TOC]

        # [[Some Page]]
        """
        let html = MarkdownRenderer.renderHTML(md)
        // Heading still becomes a wiki-link
        XCTAssertTrue(html.contains(#"data-wiki-target="Some Page""#), html)
        // TOC nav block is present and references the slug derived from text
        XCTAssertTrue(html.contains("<nav class=\"toc\">"), html)
        XCTAssertTrue(html.contains("some-page"), html)
    }

    // MARK: - Unicode token cleanup

    func testNoPrivateUseTokenLeaks() {
        let html = MarkdownRenderer.renderHTML("[[A|B]] and plain | pipe.")
        XCTAssertFalse(html.contains("\u{E110}"), "private-use token leaked to output: \(html)")
    }

    // Multi-backtick inline code is a known limitation of the naive code-span
    // detector; assert we at least clean up any leaked private-use char so the
    // visible output is never garbled, even if the wikilink stays literal.
    func testMultiBacktickCodeDoesNotLeakToken() {
        let html = MarkdownRenderer.renderHTML("Use ``[[Page|Alias]]`` here.")
        XCTAssertFalse(html.contains("\u{E110}"), "private-use token leaked: \(html)")
    }

    func testBareTokenInSourceIsRestored() {
        let html = MarkdownRenderer.renderHTML("Lorem \u{E110} ipsum.")
        XCTAssertFalse(html.contains("\u{E110}"), "private-use token leaked: \(html)")
    }

    func testCRLFLineEndingsTableStillWorks() {
        // CRLF source: ensure pre-pass line-scan doesn't break with \r tails.
        let md = "| A | B |\r\n| - | - |\r\n| [[Page|Alias]] | x |\r\n"
        let html = MarkdownRenderer.renderHTML(md)
        XCTAssertTrue(html.contains(#"data-wiki-target="Page""#), html)
        XCTAssertTrue(html.contains(#"data-wiki-alias="Alias""#), html)
        let tdCount = html.components(separatedBy: "<td").count - 1
        XCTAssertEqual(tdCount, 2, "expected 2 cells; html=\(html)")
    }

    func testIndentedFenceIsRespected() {
        // 2-space-indented fence still opens a code block in CommonMark.
        let md = """
          ```
          [[Page|Alias]]
          ```
        """
        let html = MarkdownRenderer.renderHTML(md)
        XCTAssertFalse(html.contains("wiki-link"), html)
    }

    func testTildeFenceIsRespected() {
        let md = """
        ~~~
        [[Page|Alias]]
        ~~~
        """
        let html = MarkdownRenderer.renderHTML(md)
        XCTAssertFalse(html.contains("wiki-link"), html)
    }

    func testBackslashEscapesInsideTableCell() {
        // Reporter said `[[Foo\|Bar]]` in a cell stops the table breaking but
        // doesn't render. Both must work now.
        let md = """
        | Author |
        | - |
        | [[Marcus Aurelius Antoninus\\|Marcus Aurelius]] |
        """
        let html = MarkdownRenderer.renderHTML(md)
        XCTAssertTrue(html.contains(#"data-wiki-alias="Marcus Aurelius""#), html)
        // Single-row data should be one <td>.
        let dataRow = html.components(separatedBy: "<tbody>").last ?? ""
        let tdCount = dataRow.components(separatedBy: "<td").count - 1
        XCTAssertEqual(tdCount, 1, "expected 1 cell; html=\(html)")
    }
}
