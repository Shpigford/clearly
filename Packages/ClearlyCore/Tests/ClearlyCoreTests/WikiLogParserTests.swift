import XCTest
@testable import ClearlyCore

final class WikiLogParserTests: XCTestCase {

    func testParsesSingleEntry() {
        let source = """
        # Log

        ## [2026-04-24 15:12] ingest — Ingest: gist.github.com

        Summarised the Karpathy LLM Wiki gist.

        - create `sources/karpathy-llm-wiki.md`
        - modify `index.md`
        """
        let entries = WikiLogParser.parse(source)
        XCTAssertEqual(entries.count, 1)
        let entry = entries[0]
        XCTAssertEqual(entry.timestamp, "2026-04-24 15:12")
        XCTAssertEqual(entry.kind, "ingest")
        XCTAssertEqual(entry.title, "Ingest: gist.github.com")
        XCTAssertEqual(entry.rationale, "Summarised the Karpathy LLM Wiki gist.")
        XCTAssertEqual(entry.changes.count, 2)
        XCTAssertEqual(entry.changes[0].verb, "create")
        XCTAssertEqual(entry.changes[0].path, "sources/karpathy-llm-wiki.md")
        XCTAssertEqual(entry.changes[1].verb, "modify")
        XCTAssertEqual(entry.changes[1].path, "index.md")
    }

    func testParsesMultipleEntriesNewestFirst() {
        let source = """
        # Log

        ## [2026-04-24 10:00] ingest — First

        rationale one

        - create `a.md`

        ## [2026-04-24 12:00] lint — Second

        rationale two

        - modify `b.md`
        """
        let entries = WikiLogParser.parse(source)
        XCTAssertEqual(entries.count, 2)
        // Newest first: the second heading in the file comes out first.
        XCTAssertEqual(entries[0].title, "Second")
        XCTAssertEqual(entries[1].title, "First")
    }

    func testAcceptsHyphenSeparator() {
        let source = """
        ## [2026-04-24 10:00] query - foo
        """
        let entries = WikiLogParser.parse(source)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].kind, "query")
        XCTAssertEqual(entries[0].title, "foo")
    }

    func testIgnoresNonHeadingContent() {
        let source = """
        # Log

        Some freeform notes.

        ## [2026-04-24 10:00] ingest — entry

        content
        """
        let entries = WikiLogParser.parse(source)
        XCTAssertEqual(entries.count, 1)
    }

    func testReturnsEmptyForUnparseable() {
        XCTAssertEqual(WikiLogParser.parse("").count, 0)
        XCTAssertEqual(WikiLogParser.parse("# Just a title, no entries").count, 0)
    }
}
