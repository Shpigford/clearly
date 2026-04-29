import XCTest
@testable import ClearlyCore

final class WikiLinkRewriterTests: XCTestCase {

    func testRewritesBasicLink() {
        let result = WikiLinkRewriter.rewrite(
            content: "See [[foo]] for context.",
            oldTarget: "foo.md",
            newTarget: "bar/baz.md"
        )
        XCTAssertEqual(result.newContent, "See [[bar/baz]] for context.")
        XCTAssertEqual(result.count, 1)
    }

    func testPreservesHeadingAnchor() {
        let result = WikiLinkRewriter.rewrite(
            content: "Jump to [[foo#Section A]] there.",
            oldTarget: "foo",
            newTarget: "renamed"
        )
        XCTAssertEqual(result.newContent, "Jump to [[renamed#Section A]] there.")
        XCTAssertEqual(result.count, 1)
    }

    func testPreservesAlias() {
        let result = WikiLinkRewriter.rewrite(
            content: "Inline [[foo|the foo note]] here.",
            oldTarget: "foo.md",
            newTarget: "bar.md"
        )
        XCTAssertEqual(result.newContent, "Inline [[bar|the foo note]] here.")
        XCTAssertEqual(result.count, 1)
    }

    func testPreservesBothHeadingAndAlias() {
        let result = WikiLinkRewriter.rewrite(
            content: "[[foo#Goals|see goals]]",
            oldTarget: "foo",
            newTarget: "renamed"
        )
        XCTAssertEqual(result.newContent, "[[renamed#Goals|see goals]]")
        XCTAssertEqual(result.count, 1)
    }

    func testRewritesMultipleOccurrencesOnSameLine() {
        let result = WikiLinkRewriter.rewrite(
            content: "[[foo]] then [[foo]] then [[foo|alias]]",
            oldTarget: "foo",
            newTarget: "bar"
        )
        XCTAssertEqual(result.newContent, "[[bar]] then [[bar]] then [[bar|alias]]")
        XCTAssertEqual(result.count, 3)
    }

    func testRewritesAcrossMultipleLines() {
        let content = """
        # Heading
        See [[foo]] up top.
        Some other text.
        And [[foo#bar]] later.
        """
        let result = WikiLinkRewriter.rewrite(content: content, oldTarget: "foo", newTarget: "renamed/foo")
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.newContent.contains("[[renamed/foo]]"))
        XCTAssertTrue(result.newContent.contains("[[renamed/foo#bar]]"))
    }

    func testNoOpWhenTargetAbsent() {
        let content = "Has no links to foo."
        let result = WikiLinkRewriter.rewrite(content: content, oldTarget: "foo", newTarget: "bar")
        XCTAssertEqual(result.count, 0)
        XCTAssertEqual(result.newContent, content)
    }

    func testIsCaseInsensitiveOnTargetMatch() {
        let result = WikiLinkRewriter.rewrite(
            content: "[[Foo]] and [[FOO]] and [[foo]]",
            oldTarget: "foo",
            newTarget: "renamed"
        )
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result.newContent, "[[renamed]] and [[renamed]] and [[renamed]]")
    }

    func testBareLinkMatchesPathBasename() {
        // Old target lives under a folder; bare-filename wiki-links to it
        // (e.g. `[[notes]]` referring to `journal/notes.md`) should rewrite.
        let result = WikiLinkRewriter.rewrite(
            content: "Reference [[notes]] here.",
            oldTarget: "journal/notes.md",
            newTarget: "archive/notes.md"
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.newContent, "Reference [[archive/notes]] here.")
    }

    func testPathLinkOnlyMatchesIdenticalPath() {
        // `[[a/foo]]` must NOT rewrite when oldTarget is `b/foo.md` —
        // path-form links carry intent that bare-filename links don't.
        let result = WikiLinkRewriter.rewrite(
            content: "[[a/foo]] and [[b/foo]]",
            oldTarget: "b/foo.md",
            newTarget: "z/foo.md"
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.newContent, "[[a/foo]] and [[z/foo]]")
    }

    func testReverseSplicePreservesEarlierRanges() {
        // Two adjacent links — splicing in reverse order must not corrupt
        // the earlier link's range coordinates.
        let result = WikiLinkRewriter.rewrite(
            content: "[[a]] [[a]] tail",
            oldTarget: "a",
            newTarget: "longer-replacement"
        )
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.newContent, "[[longer-replacement]] [[longer-replacement]] tail")
    }
}
