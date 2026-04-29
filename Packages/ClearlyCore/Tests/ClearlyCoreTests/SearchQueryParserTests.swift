import XCTest
@testable import ClearlyCore

final class SearchQueryParserTests: XCTestCase {

    func testEmptyQueryProducesEmptyParse() {
        let parsed = SearchQueryParser.parse("")
        XCTAssertEqual(parsed.ftsQuery, "")
        XCTAssertEqual(parsed.tagFilters, [])
        XCTAssertNil(parsed.pathPrefix)
        XCTAssertFalse(parsed.hasFilters)
    }

    func testWhitespaceOnlyProducesEmptyParse() {
        let parsed = SearchQueryParser.parse("   \t  ")
        XCTAssertEqual(parsed.ftsQuery, "")
        XCTAssertFalse(parsed.hasFilters)
    }

    func testBareTermsPassThroughUnchanged() {
        let parsed = SearchQueryParser.parse("foo bar baz")
        XCTAssertEqual(parsed.ftsQuery, "foo bar baz")
        XCTAssertEqual(parsed.tagFilters, [])
        XCTAssertNil(parsed.pathPrefix)
    }

    func testQuotedPhrasePreserved() {
        let parsed = SearchQueryParser.parse("\"flow state\" focus")
        XCTAssertEqual(parsed.ftsQuery, "\"flow state\" focus")
    }

    func testSingleTagOperator() {
        let parsed = SearchQueryParser.parse("tag:work")
        XCTAssertEqual(parsed.ftsQuery, "")
        XCTAssertEqual(parsed.tagFilters, ["work"])
        XCTAssertNil(parsed.pathPrefix)
        XCTAssertTrue(parsed.hasFilters)
    }

    func testMultipleTagOperatorsAreLowercasedAndAccumulated() {
        let parsed = SearchQueryParser.parse("tag:Work tag:URGENT")
        XCTAssertEqual(parsed.ftsQuery, "")
        XCTAssertEqual(parsed.tagFilters, ["work", "urgent"])
    }

    func testPathOperator() {
        let parsed = SearchQueryParser.parse("path:journal/2026/")
        XCTAssertEqual(parsed.ftsQuery, "")
        XCTAssertEqual(parsed.pathPrefix, "journal/2026/")
    }

    func testFirstPathOperatorWinsSubsequentIgnored() {
        let parsed = SearchQueryParser.parse("path:notes/ path:archive/")
        XCTAssertEqual(parsed.pathPrefix, "notes/")
    }

    func testMixedOperatorsAndFreeText() {
        let parsed = SearchQueryParser.parse("tag:work path:meetings/ retro")
        XCTAssertEqual(parsed.ftsQuery, "retro")
        XCTAssertEqual(parsed.tagFilters, ["work"])
        XCTAssertEqual(parsed.pathPrefix, "meetings/")
    }

    func testQuotedPhrasePlusTag() {
        let parsed = SearchQueryParser.parse("tag:idea \"local-first software\"")
        XCTAssertEqual(parsed.ftsQuery, "\"local-first software\"")
        XCTAssertEqual(parsed.tagFilters, ["idea"])
    }

    func testEmptyOperatorValueFallsThroughAsLiteralTerm() {
        let parsed = SearchQueryParser.parse("tag: foo")
        // `tag:` has no value, so it stays as a literal token.
        XCTAssertEqual(parsed.ftsQuery, "tag: foo")
        XCTAssertEqual(parsed.tagFilters, [])
    }

    func testUnknownOperatorPassesThroughVerbatim() {
        let parsed = SearchQueryParser.parse("foo:bar baseline")
        XCTAssertEqual(parsed.ftsQuery, "foo:bar baseline")
        XCTAssertEqual(parsed.tagFilters, [])
        XCTAssertNil(parsed.pathPrefix)
    }
}
