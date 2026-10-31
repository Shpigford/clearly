import XCTest
@testable import ClearlyCore

/// Code and math regions are swapped out for placeholder tokens while the
/// inline post-processors run, then restored. These tests cover documents with
/// many such regions, which used to make rendering scale with
/// (regions × document length) and hang the preview on large files.
final class MarkdownProtectedRegionTests: XCTestCase {
    func testManyCodeSpansRoundTripUnchanged() {
        let count = 2_000
        let markdown = (0..<count)
            .map { "Line \($0) has `code_\($0)` and ==mark \($0)== in it." }
            .joined(separator: "\n\n")

        let html = MarkdownRenderer.renderHTML(markdown)

        XCTAssertFalse(html.contains("__CLEARLY_PROTECTED_CODE_"), "placeholder token leaked into output")
        for i in [0, 1, 9, 10, 11, 99, 100, 101, 999, 1_000, count - 1] {
            XCTAssertTrue(html.contains("<code>code_\(i)</code>"), "missing code span \(i)")
            XCTAssertTrue(html.contains("<mark>mark \(i)</mark>"), "missing highlight \(i)")
        }
    }

    func testHighlightSyntaxInsideCodeIsNotTransformed() {
        let html = MarkdownRenderer.renderHTML("Outside ==yes== and inside `==no==` code.")
        XCTAssertTrue(html.contains("<mark>yes</mark>"), html)
        XCTAssertTrue(html.contains("<code>==no==</code>"), html)
    }

    func testLargeDocumentWithManyRegionsRendersQuickly() {
        // ~5 MB of prose with ~1,000 code spans. Before the single-pass
        // restore this took far longer than the generous bound below.
        let paragraph = String(repeating: "نص عربي طويل للاختبار ", count: 220)
        let markdown = (0..<1_000)
            .map { "\(paragraph) `c\($0)`" }
            .joined(separator: "\n\n")

        let start = Date()
        let html = MarkdownRenderer.renderHTML(markdown)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertTrue(html.contains("<code>c999</code>"))
        XCTAssertLessThan(elapsed, 20, "rendering took \(elapsed)s")
    }
}
