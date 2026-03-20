import Foundation
import cmark

enum MarkdownRenderer {
    static func renderHTML(_ markdown: String) -> String {
        guard !markdown.isEmpty else { return "" }
        let len = markdown.utf8.count
        let options = Int32(CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES | CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE | CMARK_OPT_SOURCEPOS)
        var html: String
        // Try GFM renderer first (tables, strikethrough, task lists, autolinks)
        if let buf = cmark_gfm_markdown_to_html(markdown, len, options) {
            html = String(cString: buf)
            free(buf)
        } else if let buf = cmark_markdown_to_html(markdown, len, options) {
            // Fallback to basic CommonMark
            html = String(cString: buf)
            free(buf)
        } else {
            return ""
        }
        html = processMath(html)
        return html
    }

    /// Convert $...$ and $$...$$ in rendered HTML to KaTeX-compatible spans/divs.
    /// Only transforms text nodes outside protected <code>/<pre> regions.
    private static func processMath(_ html: String) -> String {
        let (protectedHTML, protectedSegments) = protectCodeRegions(in: html)
        guard let tagRegex = try? NSRegularExpression(pattern: #"<[^>]+>"#) else {
            return restoreProtectedSegments(in: processMathText(protectedHTML), segments: protectedSegments)
        }

        var result = ""
        var lastLocation = 0
        let fullRange = NSRange(protectedHTML.startIndex..., in: protectedHTML)

        for match in tagRegex.matches(in: protectedHTML, range: fullRange) {
            let textRange = NSRange(location: lastLocation, length: match.range.location - lastLocation)
            if let range = Range(textRange, in: protectedHTML) {
                result += processMathText(String(protectedHTML[range]))
            }
            if let range = Range(match.range, in: protectedHTML) {
                result += protectedHTML[range]
            }
            lastLocation = match.range.location + match.range.length
        }

        if lastLocation < fullRange.length {
            let tailRange = NSRange(location: lastLocation, length: fullRange.length - lastLocation)
            if let range = Range(tailRange, in: protectedHTML) {
                result += processMathText(String(protectedHTML[range]))
            }
        }

        return restoreProtectedSegments(in: result, segments: protectedSegments)
    }

    private static func processMathText(_ text: String) -> String {
        var result = text
        if let blockRegex = try? NSRegularExpression(pattern: #"\$\$(.+?)\$\$"#, options: .dotMatchesLineSeparators) {
            result = blockRegex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: #"<div class="math-block">$1</div>"#
            )
        }
        if let inlineRegex = try? NSRegularExpression(pattern: #"(?<![\\$])\$(?!\$)(.+?)(?<![\\$])\$"#) {
            result = inlineRegex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: #"<span class="math-inline">$1</span>"#
            )
        }
        return result
    }

    private static func protectCodeRegions(in html: String) -> (html: String, segments: [String]) {
        guard let codeRegex = try? NSRegularExpression(
            pattern: #"<(pre|code)\b[^>]*>[\s\S]*?<\/\1>"#,
            options: [.caseInsensitive]
        ) else {
            return (html, [])
        }

        var protectedHTML = html
        var segments: [String] = []
        let matches = codeRegex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed()

        for match in matches {
            guard let range = Range(match.range, in: protectedHTML) else { continue }
            let segment = String(protectedHTML[range])
            let token = "__CLEARLY_PROTECTED_CODE_\(segments.count)__"
            segments.append(segment)
            protectedHTML.replaceSubrange(range, with: token)
        }

        return (protectedHTML, segments)
    }

    private static func restoreProtectedSegments(in html: String, segments: [String]) -> String {
        var restored = html
        for (index, segment) in segments.enumerated() {
            restored = restored.replacingOccurrences(
                of: "__CLEARLY_PROTECTED_CODE_\(index)__",
                with: segment
            )
        }
        return restored
    }
}
