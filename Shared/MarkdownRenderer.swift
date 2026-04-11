import Foundation
import cmark

enum MarkdownRenderer {
    static func renderHTML(_ markdown: String) -> String {
        guard !markdown.isEmpty else { return "" }

        let frontmatter = FrontmatterSupport.extract(from: markdown)

        let body = frontmatter?.body ?? markdown
        let len = body.utf8.count
        let options = Int32(CMARK_OPT_UNSAFE | CMARK_OPT_FOOTNOTES | CMARK_OPT_STRIKETHROUGH_DOUBLE_TILDE | CMARK_OPT_SOURCEPOS | CMARK_OPT_TABLE_PREFER_STYLE_ATTRIBUTES)
        var html: String
        // Try GFM renderer first (tables, strikethrough, task lists, autolinks)
        if let buf = cmark_gfm_markdown_to_html(body, len, options) {
            html = String(cString: buf)
            free(buf)
        } else if let buf = cmark_markdown_to_html(body, len, options) {
            // Fallback to basic CommonMark
            html = String(cString: buf)
            free(buf)
        } else {
            return ""
        }
        html = processMath(html)
        html = processCaptions(html)

        // Fix sourcepos line numbers after stripping frontmatter
        if let frontmatter, frontmatter.lineCount > 0 {
            html = adjustSourcePositions(in: html, offset: frontmatter.lineCount)
        }

        // Prepend frontmatter HTML
        if let frontmatter {
            html = frontmatterHTML(from: frontmatter) + html
        }

        return html
    }

    // MARK: - Frontmatter

    private static func frontmatterHTML(from block: FrontmatterSupport.Block) -> String {
        let sourcepos = "1:1-\(block.lineCount):1"

        if block.fields.isEmpty {
            if block.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "<div class=\"frontmatter-anchor\" data-sourcepos=\"\(sourcepos)\"></div>\n"
            }
            let escapedRaw = escapeHTML(block.rawText)
            return "<div class=\"frontmatter\" data-sourcepos=\"\(sourcepos)\"><pre>\(escapedRaw)</pre></div>\n"
        }

        var rows = ""
        for field in block.fields {
            rows += "<div class=\"frontmatter-row\"><dt>\(escapeHTML(field.key))</dt><dd>\(escapeHTML(field.value))</dd></div>"
        }
        return "<div class=\"frontmatter\" data-sourcepos=\"\(sourcepos)\"><dl>\(rows)</dl></div>\n"
    }

    private static func adjustSourcePositions(in html: String, offset: Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"data-sourcepos="(\d+):(\d+)-(\d+):(\d+)""#) else {
            return html
        }
        let nsHTML = html as NSString
        var result = ""
        var lastEnd = 0
        for match in regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            // Append text before this match
            result += nsHTML.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            let startLine = Int(nsHTML.substring(with: match.range(at: 1)))! + offset
            let startCol = nsHTML.substring(with: match.range(at: 2))
            let endLine = Int(nsHTML.substring(with: match.range(at: 3)))! + offset
            let endCol = nsHTML.substring(with: match.range(at: 4))
            result += "data-sourcepos=\"\(startLine):\(startCol)-\(endLine):\(endCol)\""
            lastEnd = match.range.location + match.range.length
        }
        result += nsHTML.substring(from: lastEnd)
        return result
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

    /// Convert "Table: caption text" paragraphs immediately before a <table> into <caption> elements.
    private static func processCaptions(_ html: String) -> String {
        guard html.contains("<table") else { return html }
        guard let regex = try? NSRegularExpression(
            pattern: #"<p[^>]*>Table:\s*(.*?)</p>\s*(<table[^>]*>)"#,
            options: [.dotMatchesLineSeparators]
        ) else { return html }
        let nsHTML = html as NSString
        return regex.stringByReplacingMatches(
            in: html,
            range: NSRange(location: 0, length: nsHTML.length),
            withTemplate: "$2<caption>$1</caption>"
        )
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
