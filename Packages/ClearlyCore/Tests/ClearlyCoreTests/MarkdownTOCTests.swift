import XCTest
@testable import ClearlyCore

final class MarkdownTOCTests: XCTestCase {
    func testTOCExpandsToNav() {
        let md = """
        # Welcome

        para

        [TOC]

        ## Section A

        text

        ### Sub

        text
        """
        let html = MarkdownRenderer.renderHTML(md)
        XCTAssertTrue(html.contains("<nav class=\"toc\">"), "TOC was not expanded")
        XCTAssertFalse(html.contains(">[TOC]<"), "Literal [TOC] left in output")
    }

    func testTOCWithFrontmatter() {
        let md = """
        ---
        title: Test
        ---

        # Welcome

        para

        [TOC]

        ## Section A
        """
        let html = MarkdownRenderer.renderHTML(md)
        XCTAssertTrue(html.contains("<nav class=\"toc\">"), "TOC with frontmatter not expanded")
    }
}
