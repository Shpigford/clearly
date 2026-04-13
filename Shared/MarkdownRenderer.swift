import Foundation
import cmark

enum MarkdownRenderer {
    static func renderHTML(_ markdown: String) -> String {
        guard !markdown.isEmpty else { return "" }

        let frontmatter = FrontmatterSupport.extract(from: markdown)

        let rawBody = frontmatter?.body ?? markdown
        let (body, codeFilenames) = extractCodeFilenames(rawBody)
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
        html = processHighlightMarks(html)
        html = processSuperSub(html)
        html = processEmoji(html)
        html = processWikiLinks(html)
        html = processCallouts(html)
        html = processTOC(html)
        html = processCaptions(html)
        html = injectCodeFilenames(html, filenames: codeFilenames)

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

    // MARK: - Code Filename Headers

    /// Pre-processing: extract `title="filename"` from fenced code info strings before cmark processes them.
    /// Returns the cleaned markdown and a mapping of source line numbers to filenames.
    private static func extractCodeFilenames(_ markdown: String) -> (String, [Int: String]) {
        guard let regex = try? NSRegularExpression(
            pattern: #"^(`{3,})(\w+)\s+title="([^"]+)"\s*$"#,
            options: .anchorsMatchLines
        ) else { return (markdown, [:]) }

        var filenames: [Int: String] = [:]
        let ns = markdown as NSString
        var cleaned = ""
        var lastEnd = 0
        let lines = markdown.components(separatedBy: "\n")
        var lineStart = 0

        for (lineIdx, line) in lines.enumerated() {
            let lineRange = NSRange(location: lineStart, length: (line as NSString).length)
            if let match = regex.firstMatch(in: markdown, range: lineRange) {
                let fence = ns.substring(with: match.range(at: 1))
                let lang = ns.substring(with: match.range(at: 2))
                let filename = ns.substring(with: match.range(at: 3))
                filenames[lineIdx + 1] = filename // 1-indexed
                // Replace with just fence + lang (strip title)
                cleaned += ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                cleaned += "\(fence)\(lang)"
                lastEnd = match.range.location + match.range.length
            }
            lineStart += (line as NSString).length + 1 // +1 for \n
        }
        cleaned += ns.substring(from: lastEnd)
        return (cleaned, filenames)
    }

    /// Post-processing: inject `<div class="code-filename">` before `<pre>` blocks that had title= attributes.
    private static func injectCodeFilenames(_ html: String, filenames: [Int: String]) -> String {
        guard !filenames.isEmpty else { return html }
        guard let regex = try? NSRegularExpression(pattern: #"<pre data-sourcepos="(\d+):\d+-\d+:\d+""#) else { return html }
        let ns = html as NSString
        var result = ""
        var lastEnd = 0
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let lineStr = ns.substring(with: match.range(at: 1))
            guard let line = Int(lineStr), let filename = filenames[line] else {
                continue
            }
            let prefix = ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            result += prefix
            result += "<div class=\"code-filename\">\(escapeHTML(filename))</div>"
            lastEnd = match.range.location
        }
        result += ns.substring(from: lastEnd)
        return result
    }

    // MARK: - Wiki-Links [[note]]

    private static func processWikiLinks(_ html: String) -> String {
        let (protectedHTML, segments) = protectWikiLinkRegions(in: html)
        guard let regex = try? NSRegularExpression(
            pattern: #"\[\[([^\]\|#\^]+?)(?:#([^\]\|]+?))?(?:\|([^\]]+?))?\]\]"#
        ) else {
            return restoreWikiLinkRegions(in: protectedHTML, segments: segments)
        }
        let ns = protectedHTML as NSString
        var result = ""
        var lastEnd = 0
        for match in regex.matches(in: protectedHTML, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))

            let target = ns.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespaces)

            var heading: String? = nil
            if match.range(at: 2).location != NSNotFound {
                heading = ns.substring(with: match.range(at: 2))
                    .trimmingCharacters(in: .whitespaces)
            }

            let displayText: String
            if match.range(at: 3).location != NSNotFound {
                displayText = ns.substring(with: match.range(at: 3))
                    .trimmingCharacters(in: .whitespaces)
            } else if let heading {
                displayText = "\(target) > \(heading)"
            } else {
                displayText = target
            }

            let encodedTarget = target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target
            var href = "clearly://wiki/\(encodedTarget)"
            if let heading {
                let encodedHeading = heading.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? heading
                href += "#\(encodedHeading)"
            }

            result += "<a href=\"\(href)\" class=\"wiki-link\">\(escapeHTML(displayText))</a>"
            lastEnd = match.range.location + match.range.length
        }
        result += ns.substring(from: lastEnd)
        return restoreWikiLinkRegions(in: result, segments: segments)
    }

    private static func protectWikiLinkRegions(in html: String) -> (html: String, segments: [String]) {
        guard let regex = try? NSRegularExpression(
            pattern: #"<(pre|code|a|script|style)\b[^>]*>[\s\S]*?<\/\1>"#,
            options: [.caseInsensitive]
        ) else {
            return (html, [])
        }

        var protectedHTML = html
        var segments: [String] = []
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed()

        for match in matches {
            guard let range = Range(match.range, in: protectedHTML) else { continue }
            let segment = String(protectedHTML[range])
            let token = "__CLEARLY_PROTECTED_WIKILINK_\(segments.count)__"
            segments.append(segment)
            protectedHTML.replaceSubrange(range, with: token)
        }

        return (protectedHTML, segments)
    }

    private static func restoreWikiLinkRegions(in html: String, segments: [String]) -> String {
        var restored = html
        for (index, segment) in segments.enumerated() {
            restored = restored.replacingOccurrences(
                of: "__CLEARLY_PROTECTED_WIKILINK_\(index)__",
                with: segment
            )
        }
        return restored
    }

    // MARK: - Highlight/Mark ==text==

    private static func processHighlightMarks(_ html: String) -> String {
        let (protectedHTML, segments) = protectCodeRegions(in: html)
        guard let regex = try? NSRegularExpression(pattern: #"==([^=\n]+?)=="#) else {
            return restoreProtectedSegments(in: protectedHTML, segments: segments)
        }
        let ns = protectedHTML as NSString
        let result = regex.stringByReplacingMatches(
            in: protectedHTML,
            range: NSRange(location: 0, length: ns.length),
            withTemplate: "<mark>$1</mark>"
        )
        return restoreProtectedSegments(in: result, segments: segments)
    }

    // MARK: - Superscript/Subscript

    private static func processSuperSub(_ html: String) -> String {
        let (protectedHTML, segments) = protectCodeRegions(in: html)
        var result = protectedHTML
        // Superscript: ^text^ (not ^^)
        if let supRegex = try? NSRegularExpression(pattern: #"(?<!\^)\^(?!\^)([^\^\s\n]+?)(?<!\^)\^(?!\^)"#) {
            let ns = result as NSString
            result = supRegex.stringByReplacingMatches(
                in: result,
                range: NSRange(location: 0, length: ns.length),
                withTemplate: "<sup>$1</sup>"
            )
        }
        // Subscript: ~text~ (not ~~)
        if let subRegex = try? NSRegularExpression(pattern: #"(?<!~)~(?!~)([^~\s\n]+?)(?<!~)~(?!~)"#) {
            let ns = result as NSString
            result = subRegex.stringByReplacingMatches(
                in: result,
                range: NSRange(location: 0, length: ns.length),
                withTemplate: "<sub>$1</sub>"
            )
        }
        return restoreProtectedSegments(in: result, segments: segments)
    }

    // MARK: - Emoji Shortcodes

    private static func processEmoji(_ html: String) -> String {
        let (protectedHTML, segments) = protectCodeRegions(in: html)
        guard let tagRegex = try? NSRegularExpression(pattern: #"<[^>]+>"#),
              let emojiRegex = try? NSRegularExpression(pattern: #":([a-z0-9_+-]+):"#) else {
            return restoreProtectedSegments(in: protectedHTML, segments: segments)
        }

        var result = ""
        var lastLocation = 0
        let fullRange = NSRange(protectedHTML.startIndex..., in: protectedHTML)

        for match in tagRegex.matches(in: protectedHTML, range: fullRange) {
            let textRange = NSRange(location: lastLocation, length: match.range.location - lastLocation)
            if let range = Range(textRange, in: protectedHTML) {
                result += replacingEmojiShortcodes(in: String(protectedHTML[range]), regex: emojiRegex)
            }
            if let range = Range(match.range, in: protectedHTML) {
                result += protectedHTML[range]
            }
            lastLocation = match.range.location + match.range.length
        }

        if lastLocation < fullRange.length {
            let tailRange = NSRange(location: lastLocation, length: fullRange.length - lastLocation)
            if let range = Range(tailRange, in: protectedHTML) {
                result += replacingEmojiShortcodes(in: String(protectedHTML[range]), regex: emojiRegex)
            }
        }

        return restoreProtectedSegments(in: result, segments: segments)
    }

    private static func replacingEmojiShortcodes(in text: String, regex: NSRegularExpression) -> String {
        let ns = text as NSString
        var result = ""
        var lastEnd = 0

        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            let shortcode = ns.substring(with: match.range(at: 1))
            result += EmojiShortcodes.lookup[shortcode] ?? ns.substring(with: match.range)
            lastEnd = match.range.location + match.range.length
        }

        result += ns.substring(from: lastEnd)
        return result
    }

    // MARK: - Callouts/Admonitions

    private static let calloutTypes: [String: (icon: String, label: String)] = [
        "note": ("\u{2139}\u{FE0F}", "Note"),
        "tip": ("\u{2600}\u{FE0F}", "Tip"),
        "important": ("\u{2757}", "Important"),
        "warning": ("\u{26A0}\u{FE0F}", "Warning"),
        "caution": ("\u{26D4}", "Caution"),
        "abstract": ("\u{1F4CB}", "Abstract"),
        "todo": ("\u{2611}\u{FE0F}", "Todo"),
        "example": ("\u{1F4DD}", "Example"),
        "quote": ("\u{275D}", "Quote"),
        "bug": ("\u{1F41B}", "Bug"),
        "danger": ("\u{26A1}", "Danger"),
        "failure": ("\u{2717}", "Failure"),
        "success": ("\u{2713}", "Success"),
        "question": ("\u{003F}", "Question"),
        "info": ("\u{2139}\u{FE0F}", "Info"),
    ]

    private static func processCallouts(_ html: String) -> String {
        guard html.contains("[!") else { return html }
        // Match blockquote containing [!TYPE] at the start.
        // Group 5 captures title on the same line as [!TYPE].
        // Group 6 captures remaining content inside the first <p> (may span newlines).
        // Group 7 captures content after the first </p>.
        guard let regex = try? NSRegularExpression(
            pattern: #"<blockquote([^>]*)>\s*<p([^>]*)>\[!([\w]+)\](-?)[ \t]*([^\n]*)\n?([\s\S]*?)</p>([\s\S]*?)</blockquote>"#,
            options: []
        ) else { return html }
        let ns = html as NSString
        var result = ""
        var lastEnd = 0
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            let bqAttrs = ns.substring(with: match.range(at: 1))
            let typeStr = ns.substring(with: match.range(at: 3)).lowercased()
            let foldable = ns.substring(with: match.range(at: 4)) == "-"
            let titleText = ns.substring(with: match.range(at: 5)).trimmingCharacters(in: .whitespaces)
            let firstParaContent = ns.substring(with: match.range(at: 6)).trimmingCharacters(in: .whitespacesAndNewlines)
            let restContent = ns.substring(with: match.range(at: 7))

            let info = calloutTypes[typeStr] ?? ("\u{2139}\u{FE0F}", typeStr.capitalized)
            let displayTitle = titleText.isEmpty ? info.label : titleText

            // Build content from remaining first-paragraph text + rest of blockquote
            var contentHTML = ""
            if !firstParaContent.isEmpty {
                contentHTML += "<p>\(firstParaContent)</p>"
            }
            contentHTML += restContent

            if foldable {
                result += """
                <details class="callout callout-\(typeStr)"\(bqAttrs)>\
                <summary class="callout-title"><span class="callout-icon">\(info.icon)</span> \
                <span class="callout-title-text">\(displayTitle)</span></summary>\
                <div class="callout-content">\(contentHTML)</div></details>
                """
            } else {
                result += """
                <div class="callout callout-\(typeStr)"\(bqAttrs)>\
                <div class="callout-title"><span class="callout-icon">\(info.icon)</span> \
                <span class="callout-title-text">\(displayTitle)</span></div>\
                <div class="callout-content">\(contentHTML)</div></div>
                """
            }
            lastEnd = match.range.location + match.range.length
        }
        result += ns.substring(from: lastEnd)
        return result
    }

    // MARK: - Table of Contents

    private static func processTOC(_ html: String) -> String {
        guard html.contains("[TOC]") else { return html }
        // Parse headings from the HTML
        guard let headingRegex = try? NSRegularExpression(pattern: #"<(h[1-6])([^>]*)>(.*?)</\1>"#, options: .dotMatchesLineSeparators) else { return html }
        let ns = html as NSString
        var headings: [(level: Int, text: String, id: String)] = []
        var usedIDs: [String: Int] = [:]
        for match in headingRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range(at: 1))
            let level = Int(String(tag.last!)) ?? 1
            let attrs = ns.substring(with: match.range(at: 2))
            let rawText = ns.substring(with: match.range(at: 3))
            // Strip HTML tags from heading text
            let text = rawText.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            let baseID = headingID(from: text, existingAttributes: attrs)
            let id = uniqueHeadingID(baseID, usedIDs: &usedIDs)
            headings.append((level: level, text: text, id: id))
        }
        guard !headings.isEmpty else { return html }

        // Add or update id attributes on headings in the HTML so TOC links always resolve.
        var withIDs = html
        var offset = 0
        for (index, match) in headingRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)).enumerated() {
            guard index < headings.count else { break }
            let tag = ns.substring(with: match.range(at: 1))
            let attrs = ns.substring(with: match.range(at: 2))
            let replacement = "<\(tag)\(updatingHeadingAttributes(attrs, id: headings[index].id))>"
            let matchText = ns.substring(with: match.range)
            guard let openTagEnd = matchText.firstIndex(of: ">") else { continue }
            let openTagLength = matchText.distance(from: matchText.startIndex, to: matchText.index(after: openTagEnd))
            let replacementRange = NSRange(location: match.range.location + offset, length: openTagLength)
            withIDs = (withIDs as NSString).replacingCharacters(in: replacementRange, with: replacement)
            offset += (replacement as NSString).length - openTagLength
        }

        // Build TOC HTML
        let minLevel = headings.map(\.level).min() ?? 1
        var tocHTML = "<nav class=\"toc\"><ul>"
        var prevLevel = minLevel
        for heading in headings {
            let level = heading.level
            if level > prevLevel {
                for _ in 0..<(level - prevLevel) { tocHTML += "<ul>" }
            } else if level < prevLevel {
                for _ in 0..<(prevLevel - level) { tocHTML += "</ul></li>" }
            } else if heading.id != headings.first?.id {
                tocHTML += "</li>"
            }
            tocHTML += "<li><a href=\"#\(heading.id)\">\(heading.text)</a>"
            prevLevel = level
        }
        for _ in 0..<(prevLevel - minLevel) { tocHTML += "</li></ul>" }
        tocHTML += "</li></ul></nav>"

        // Replace [TOC] paragraph
        if let tocRegex = try? NSRegularExpression(pattern: #"<p[^>]*>\[TOC\]</p>"#, options: .caseInsensitive) {
            let nsResult = withIDs as NSString
            withIDs = tocRegex.stringByReplacingMatches(
                in: withIDs,
                range: NSRange(location: 0, length: nsResult.length),
                withTemplate: tocHTML
            )
        }
        return withIDs
    }

    private static func headingID(from text: String, existingAttributes attrs: String) -> String {
        if let existingID = existingHeadingID(in: attrs), !existingID.isEmpty {
            return existingID
        }

        let slug = text.lowercased()
            .replacingOccurrences(of: "[^\\w\\s-]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return slug.isEmpty ? "section" : slug
    }

    private static func uniqueHeadingID(_ baseID: String, usedIDs: inout [String: Int]) -> String {
        let count = usedIDs[baseID, default: 0]
        usedIDs[baseID] = count + 1
        return count == 0 ? baseID : "\(baseID)-\(count)"
    }

    private static func existingHeadingID(in attrs: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"id=(["'])(.*?)\1"#) else { return nil }
        let ns = attrs as NSString
        guard let match = regex.firstMatch(in: attrs, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 3 else { return nil }
        return ns.substring(with: match.range(at: 2))
    }

    private static func updatingHeadingAttributes(_ attrs: String, id: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(\s*)id=(["']).*?\2"#) else {
            return attrs + " id=\"\(id)\""
        }

        let ns = attrs as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard regex.firstMatch(in: attrs, range: range) != nil else {
            return attrs + " id=\"\(id)\""
        }

        return regex.stringByReplacingMatches(in: attrs, range: range, withTemplate: " id=\"\(id)\"")
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
