import XCTest
@testable import ClearlyCore

final class TextMatcherTests: XCTestCase {
    func testEmptyQueryReturnsNoRanges() {
        XCTAssertEqual(TextMatcher.ranges(of: "", in: "anything"), [])
    }

    func testEmptyTextReturnsNoRanges() {
        XCTAssertEqual(TextMatcher.ranges(of: "foo", in: ""), [])
    }

    func testNoMatchesReturnsEmpty() {
        XCTAssertEqual(TextMatcher.ranges(of: "xyz", in: "hello world"), [])
    }

    func testSingleMatch() {
        let ranges = TextMatcher.ranges(of: "world", in: "hello world")
        XCTAssertEqual(ranges, [NSRange(location: 6, length: 5)])
    }

    func testMultipleNonOverlappingMatches() {
        let ranges = TextMatcher.ranges(of: "ab", in: "ababab")
        XCTAssertEqual(ranges, [
            NSRange(location: 0, length: 2),
            NSRange(location: 2, length: 2),
            NSRange(location: 4, length: 2),
        ])
    }

    func testCaseInsensitiveByDefault() {
        let ranges = TextMatcher.ranges(of: "Foo", in: "foo FOO fOo")
        XCTAssertEqual(ranges, [
            NSRange(location: 0, length: 3),
            NSRange(location: 4, length: 3),
            NSRange(location: 8, length: 3),
        ])
    }

    func testCaseSensitiveExcludesMismatches() {
        let ranges = TextMatcher.ranges(of: "Foo", in: "foo Foo FOO", caseSensitive: true)
        XCTAssertEqual(ranges, [NSRange(location: 4, length: 3)])
    }

    func testMatchAtEndOfText() {
        let ranges = TextMatcher.ranges(of: "end", in: "at the end")
        XCTAssertEqual(ranges, [NSRange(location: 7, length: 3)])
    }

    func testMultilineText() {
        let text = "line one\nline two\nline three"
        let ranges = TextMatcher.ranges(of: "line", in: text)
        XCTAssertEqual(ranges, [
            NSRange(location: 0, length: 4),
            NSRange(location: 9, length: 4),
            NSRange(location: 18, length: 4),
        ])
    }
}
