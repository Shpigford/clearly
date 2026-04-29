import XCTest
@testable import ClearlyCore

final class ReplaceEngineTests: XCTestCase {
    func testPlainSubstitutionIgnoresTemplateMetacharacters() {
        let match = TextMatch(range: NSRange(location: 0, length: 3), captureRanges: [])
        XCTAssertEqual(
            ReplaceEngine.substitution(for: match, in: "foo bar", template: "$1!", isRegex: false),
            "$1!"
        )
    }

    func testRegexCaptureGroupSubstitution() throws {
        let matches = try TextMatcher.matches(of: "(\\w+)@(\\w+)",
                                              in: "hi alice@example world",
                                              options: TextMatchOptions(useRegex: true))
        XCTAssertEqual(matches.count, 1)
        let result = ReplaceEngine.substitution(for: matches[0],
                                                in: "hi alice@example world",
                                                template: "<$1 at $2>",
                                                isRegex: true)
        XCTAssertEqual(result, "<alice at example>")
    }

    func testReplaceAllPreservesOrderAndIndices() throws {
        let text = "ab ab ab"
        let matches = try TextMatcher.matches(of: "ab", in: text, options: TextMatchOptions())
        XCTAssertEqual(matches.count, 3)
        let out = ReplaceEngine.applyAll(matches: matches, in: text, template: "X", isRegex: false)
        XCTAssertEqual(out, "X X X")
    }

    func testReplaceAllRegexExpandsCaptures() throws {
        let text = "alpha beta gamma"
        let matches = try TextMatcher.matches(of: "(\\w+)", in: text, options: TextMatchOptions(useRegex: true))
        XCTAssertEqual(matches.count, 3)
        let out = ReplaceEngine.applyAll(matches: matches, in: text, template: "[$1]", isRegex: true)
        XCTAssertEqual(out, "[alpha] [beta] [gamma]")
    }

    func testEscapedDollarSignIsLiteral() throws {
        let matches = try TextMatcher.matches(of: "(\\w+)", in: "hello", options: TextMatchOptions(useRegex: true))
        let out = ReplaceEngine.substitution(for: matches[0], in: "hello", template: "\\$1=$1", isRegex: true)
        XCTAssertEqual(out, "$1=hello")
    }

    func testWholeWordOptionMatchesOnlyWordBoundaries() throws {
        let matches = try TextMatcher.matches(
            of: "cat",
            in: "concatenate the cat",
            options: TextMatchOptions(wholeWord: true)
        )
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].range, NSRange(location: 16, length: 3))
    }

    func testInvalidRegexThrows() {
        XCTAssertThrowsError(
            try TextMatcher.matches(of: "[invalid", in: "anything", options: TextMatchOptions(useRegex: true))
        ) { error in
            guard case TextMatcherError.invalidRegex = error else {
                return XCTFail("Expected invalidRegex, got \(error)")
            }
        }
    }
}
