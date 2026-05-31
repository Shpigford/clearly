import XCTest
@testable import ClearlyCore

/// Rendering of the frontmatter block in the preview, in particular that
/// layout-directive keys (`wrapIndent` / `firstLineIndent`) are hidden.
final class MarkdownFrontmatterTests: XCTestCase {

    func testContentFieldsAreRendered() {
        let md = """
        ---
        title: Notes
        author: Me
        ---
        body
        """
        let html = MarkdownRenderer.renderHTML(md)
        XCTAssertTrue(html.contains("<dl>"), "content frontmatter should render a definition list")
        XCTAssertTrue(html.contains("<dt>title</dt><dd>Notes</dd>"))
        XCTAssertTrue(html.contains("<dt>author</dt><dd>Me</dd>"))
    }

    func testLayoutKeysAreHiddenButContentKeysRemain() {
        let md = """
        ---
        title: Notes
        wrapIndent: 2em
        firstLineIndent: 0
        ---
        body
        """
        let html = MarkdownRenderer.renderHTML(md)
        XCTAssertTrue(html.contains("<dt>title</dt><dd>Notes</dd>"), "content key should still render")
        XCTAssertFalse(html.contains("wrapIndent"), "layout key wrapIndent should be hidden from preview")
        XCTAssertFalse(html.contains("firstLineIndent"), "layout key firstLineIndent should be hidden from preview")
    }

    /// When the frontmatter contains ONLY layout directives, the preview must not
    /// render a visible frontmatter block — just the silent anchor that keeps the
    /// source-position mapping intact.
    func testOnlyLayoutKeysRendersNoFrontmatterBlock() {
        let md = """
        ---
        wrapIndent: 11
        firstLineIndent: 0
        ---
        body
        """
        let html = MarkdownRenderer.renderHTML(md)
        XCTAssertFalse(html.contains("<dl>"), "no definition list when all keys are layout directives")
        XCTAssertFalse(html.contains("frontmatter-row"), "no rows when all keys are hidden")
        XCTAssertFalse(html.contains("wrapIndent"), "layout key must not leak into output")
        XCTAssertTrue(html.contains("class=\"frontmatter-anchor\""), "should emit the silent anchor")
    }

    func testNoFrontmatterEmitsNoFrontmatterMarkup() {
        let html = MarkdownRenderer.renderHTML("# Title\n\nbody")
        XCTAssertFalse(html.contains("class=\"frontmatter"), "plain document should not emit a frontmatter block")
    }
}
