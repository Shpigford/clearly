import Foundation
import cmark

enum MarkdownRenderer {
    static func renderHTML(_ markdown: String) -> String {
        guard !markdown.isEmpty else { return "" }
        let len = markdown.utf8.count
        let options = Int32(CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES | CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE | CMARK_OPT_SOURCEPOS)
        // Try GFM renderer first (tables, strikethrough, task lists, autolinks)
        if let buf = cmark_gfm_markdown_to_html(markdown, len, options) {
            let html = String(cString: buf)
            free(buf)
            return html
        }
        // Fallback to basic CommonMark
        if let buf = cmark_markdown_to_html(markdown, len, options) {
            let html = String(cString: buf)
            free(buf)
            return html
        }
        return ""
    }
}
