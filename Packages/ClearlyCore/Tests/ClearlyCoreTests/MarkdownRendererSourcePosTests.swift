import XCTest
@testable import ClearlyCore

final class MarkdownRendererSourcePosTests: XCTestCase {
    func testSourceLineOffsetShiftsDataSourceLine() {
        let md = "# Heading\n\npara\n"
        let html0 = MarkdownRenderer.renderHTML(md)
        let html5 = MarkdownRenderer.renderHTML(md, sourceLineOffset: 5)

        XCTAssertTrue(html0.contains("data-sourcepos=\"1:1-1:9\""), html0)
        XCTAssertTrue(html5.contains("data-sourcepos=\"6:1-6:9\""), html5)
    }

    func testFrontmatterAndExplicitOffsetCombine() {
        let md = """
---
title: hi
---

# Heading
"""
        let html = MarkdownRenderer.renderHTML(md, sourceLineOffset: 10)
        // frontmatter is 3 lines → body line 2 of 2 is heading. With
        // 3 + 10 = 13 offset added to cmark's body sourcepos line 2,
        // heading lands on line 15.
        XCTAssertTrue(html.contains("data-sourcepos=\"15:1-15:9\""), html)
    }
}
