import AppKit
import os

final class MarkdownSyntaxHighlighter: NSObject {

    private var isHighlighting = false
    private var cachedProtectedRanges: [ProtectedRange] = []

    // MARK: - Regex Patterns

    private static let frontmatterKeyRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "^([\\w][\\w\\s.-]*)(:)",
        options: .anchorsMatchLines
    )

    private static let patterns: [(NSRegularExpression, HighlightStyle)] = {
        var result: [(NSRegularExpression, HighlightStyle)] = []

        func add(_ pattern: String, _ style: HighlightStyle, options: NSRegularExpression.Options = []) {
            if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                result.append((regex, style))
            }
        }

        // Frontmatter (--- ... ---) at very start of file — must come before everything
        add("\\A---[ \\t]*\\n([\\s\\S]*?)\\n---[ \\t]*(?:\\n|\\z)", .frontmatter)

        // Fenced code blocks (``` ... ```) — must come first to prevent inner highlighting
        add("^(`{3,})(.*?)\\n([\\s\\S]*?)^\\1\\s*$", .codeBlock, options: .anchorsMatchLines)

        // Display math blocks: $$...$$ (multiline)
        add("^\\$\\$\\n([\\s\\S]*?)^\\$\\$\\s*$", .mathBlock, options: .anchorsMatchLines)

        // Inline math: $...$
        add("(?<!\\$)\\$(?!\\$)([^\n$]+?)(?<!\\$)\\$(?!\\$)", .mathInline)

        // Headings: # Heading
        add("^(#{1,6}\\s+)(.+)$", .heading, options: .anchorsMatchLines)

        // Bold italic: ***text*** or ___text___
        add("(\\*\\*\\*|___)(.+?)(\\1)", .boldItalic)

        // Bold: **text** or __text__ (not part of ***triple***)
        add("(?<![*_])(\\*\\*(?!\\*)|__(?!_))(.+?)(\\1)(?![*_])", .bold)

        // Italic: *text* or _text_ (not inside words for _)
        add("(?<![\\w*])(\\*(?!\\*)|_(?!_))(?!\\s)(.+?)(?<!\\s)\\1(?![\\w*])", .italic)

        // Strikethrough: ~~text~~
        add("(~~)([^\n]+?)(~~)", .strikethrough)

        // Inline code: `code`
        add("(`+)([^\n]+?)(\\1)", .inlineCode)

        // Images: ![alt](src) — must come before links
        add("(!\\[)([^\\]\n]*)(\\]\\([^\n]+?\\))", .link)

        // Links: [text](url)
        add("(\\[)([^\n]+?)(\\]\\([^\n]+?\\))", .link)

        // Reference links: [text][ref]
        add("(\\[)([^\\]\n]+)(\\])(\\[)([^\\]\n]*)(\\])", .link)

        // Blockquotes: > text
        add("^(>+\\s?)(.*)$", .blockquote, options: .anchorsMatchLines)

        // Unordered list markers: - or * or +
        add("^(\\s*[-*+]\\s)", .listMarker, options: .anchorsMatchLines)

        // Ordered list markers: 1.
        add("^(\\s*\\d+\\.\\s)", .listMarker, options: .anchorsMatchLines)

        // Task list: - [ ] or - [x]
        add("^(\\s*[-*+]\\s\\[[ xX]\\]\\s)", .listMarker, options: .anchorsMatchLines)

        // Horizontal rule
        add("^([-*_]{3,})\\s*$", .syntax, options: .anchorsMatchLines)

        // Highlight/Mark: ==text==
        add("(==)([^=\n]+?)(==)", .highlight)

        // Footnote markers: [^ref]
        add("(\\[\\^)([^\\]\n]+)(\\])", .footnote)

        // Wiki-links: [[note]] or [[note|alias]] or [[note#heading]]
        add(#"(\[\[)([^\]\n]+?)(\]\])"#, .wikiLink)

        // Table rows: lines with pipes
        add("^(\\|.+\\|)\\s*$", .syntax, options: .anchorsMatchLines)

        // Setext headings: text followed by === or --- on next line
        add("^(.+)\\n(={3,}|-{3,})\\s*$", .heading, options: .anchorsMatchLines)

        // HTML tags
        add("(</?[a-zA-Z][a-zA-Z0-9]*(?:\\s+[^>]*)?>)", .htmlTag)

        return result
    }()

    // MARK: - Highlight Styles

    private enum HighlightStyle {
        case heading
        case bold
        case boldItalic
        case italic
        case strikethrough
        case inlineCode
        case codeBlock
        case link
        case blockquote
        case listMarker
        case syntax
        case mathBlock
        case mathInline
        case frontmatter
        case highlight
        case footnote
        case wikiLink
        case htmlTag
    }

    private enum ProtectedBlockKind {
        case code
        case math
        case frontmatter
    }

    private struct ProtectedRange {
        var range: NSRange
        let kind: ProtectedBlockKind
    }

    // MARK: - Highlighting

    func highlightAll(_ textStorage: NSTextStorage, caller: String = "") {
        guard !isHighlighting else { return }
        isHighlighting = true
        defer { isHighlighting = false }
        let startTime = CACurrentMediaTime()

        textStorage.beginEditing()
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let text = textStorage.string

        // Reset to default style
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Theme.editorLineHeight
        paragraph.maximumLineHeight = Theme.editorLineHeight

        textStorage.addAttributes([
            .font: Theme.editorFont,
            .foregroundColor: Theme.textColor,
            .paragraphStyle: paragraph,
            .baselineOffset: Theme.editorBaselineOffset
        ], range: fullRange)

        // Track code block ranges to skip inner highlighting
        var protectedRanges: [ProtectedRange] = []

        for (regex, style) in Self.patterns {
            regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let match = match else { return }

                // If this isn't a code/math/frontmatter block pattern, skip if inside a protected block
                if style != .codeBlock && style != .mathBlock && style != .frontmatter {
                    let matchRange = match.range
                    if protectedRanges.contains(where: { NSIntersectionRange($0.range, matchRange).length > 0 }) {
                        return
                    }
                }

                switch style {
                case .heading:
                    // Group 1: syntax (##), Group 2: content
                    if match.numberOfRanges >= 3 {
                        let syntaxRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: syntaxRange)
                        textStorage.addAttributes([
                            .foregroundColor: Theme.headingColor,
                            .font: NSFont.monospacedSystemFont(ofSize: Theme.editorFontSize + 4, weight: .bold)
                        ], range: contentRange)
                    }

                case .bold:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttributes([
                            .foregroundColor: Theme.boldColor,
                            .font: NSFont.monospacedSystemFont(ofSize: Theme.editorFontSize, weight: .bold)
                        ], range: contentRange)
                    }

                case .boldItalic:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        let boldItalicFont = NSFontManager.shared.convert(
                            NSFont.monospacedSystemFont(ofSize: Theme.editorFontSize, weight: .bold),
                            toHaveTrait: .italicFontMask
                        )
                        textStorage.addAttributes([
                            .foregroundColor: Theme.boldColor,
                            .font: boldItalicFont
                        ], range: contentRange)
                    }

                case .italic:
                    if match.numberOfRanges >= 3 {
                        let syntaxRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: syntaxRange)
                        // Apply to the closing marker too
                        let closingStart = match.range(at: 2).upperBound
                        let closingRange = NSRange(location: closingStart, length: match.range(at: 1).length)
                        if closingRange.upperBound <= textStorage.length {
                            textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: closingRange)
                        }
                        let italicFont = NSFontManager.shared.convert(Theme.editorFont, toHaveTrait: .italicFontMask)
                        textStorage.addAttributes([
                            .foregroundColor: Theme.italicColor,
                            .font: italicFont
                        ], range: contentRange)
                    }

                case .strikethrough:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttributes([
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                            .foregroundColor: Theme.syntaxColor
                        ], range: contentRange)
                    }

                case .inlineCode:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.codeColor, range: contentRange)
                    }

                case .codeBlock:
                    protectedRanges.append(ProtectedRange(range: match.range, kind: .code))
                    // Fade the entire block
                    textStorage.addAttribute(.foregroundColor, value: Theme.codeColor, range: match.range)
                    // Fade the fences specifically
                    if match.numberOfRanges >= 2 {
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: match.range(at: 1))
                    }

                case .link:
                    if match.numberOfRanges >= 4 {
                        let bracketRange = match.range(at: 1)
                        let textRange = match.range(at: 2)
                        let urlPartRange = match.range(at: 3)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: bracketRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.linkColor, range: textRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: urlPartRange)
                    }

                case .blockquote:
                    if match.numberOfRanges >= 3 {
                        let markerRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: markerRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.blockquoteColor, range: contentRange)
                    }

                case .listMarker:
                    textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: match.range)

                case .syntax:
                    textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: match.range)

                case .mathBlock:
                    protectedRanges.append(ProtectedRange(range: match.range, kind: .math))
                    textStorage.addAttribute(.foregroundColor, value: Theme.mathColor, range: match.range)
                    // Fade the opening $$ delimiter
                    let openRange = NSRange(location: match.range.location, length: 2)
                    if openRange.upperBound <= textStorage.length {
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: openRange)
                    }
                    // Fade the closing $$ delimiter
                    let closeStart = match.range.location + match.range.length - 2
                    let closeRange = NSRange(location: closeStart, length: 2)
                    if closeRange.upperBound <= textStorage.length && closeStart >= match.range.location {
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                    }

                case .mathInline:
                    if match.numberOfRanges >= 2 {
                        let contentRange = match.range(at: 1)
                        let openRange = NSRange(location: match.range.location, length: 1)
                        let closeRange = NSRange(location: match.range.location + match.range.length - 1, length: 1)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.mathColor, range: contentRange)
                    }

                case .highlight:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttributes([
                            .foregroundColor: Theme.highlightColor,
                            .backgroundColor: Theme.highlightBackgroundColor
                        ], range: contentRange)
                    }

                case .footnote:
                    textStorage.addAttribute(.foregroundColor, value: Theme.footnoteColor, range: match.range)

                case .wikiLink:
                    if match.numberOfRanges >= 4 {
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: match.range(at: 1))
                        textStorage.addAttribute(.foregroundColor, value: Theme.wikiLinkColor, range: match.range(at: 2))
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: match.range(at: 3))
                    }

                case .htmlTag:
                    textStorage.addAttribute(.foregroundColor, value: Theme.htmlTagColor, range: match.range)

                case .frontmatter:
                    let matchedText = (text as NSString).substring(with: match.range)
                    guard FrontmatterSupport.extract(from: matchedText) != nil else { return }
                    protectedRanges.append(ProtectedRange(range: match.range, kind: .frontmatter))
                    let nsText = text as NSString
                    // Base color for the whole block
                    textStorage.addAttribute(.foregroundColor, value: Theme.frontmatterColor, range: match.range)
                    // Color the opening --- delimiter line
                    let openLineEnd = nsText.range(of: "\n", range: NSRange(location: match.range.location, length: match.range.length))
                    if openLineEnd.location != NSNotFound {
                        let openRange = NSRange(location: match.range.location, length: openLineEnd.location - match.range.location)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: openRange)
                    }
                    // Color the closing --- delimiter (last line of match)
                    let matchStr = nsText.substring(with: match.range) as NSString
                    let lastNewline = matchStr.range(of: "\n", options: .backwards)
                    if lastNewline.location != NSNotFound {
                        let closeStart = match.range.location + lastNewline.location + 1
                        let closeLen = match.range.location + match.range.length - closeStart
                        if closeLen > 0 {
                            let closeRange = NSRange(location: closeStart, length: closeLen)
                            textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        }
                    }
                    // Color YAML keys within the body (group 1)
                    if match.numberOfRanges >= 2 {
                        let bodyRange = match.range(at: 1)
                        if bodyRange.location != NSNotFound, let keyRegex = Self.frontmatterKeyRegex {
                            keyRegex.enumerateMatches(in: text, range: bodyRange) { keyMatch, _, _ in
                                guard let keyMatch = keyMatch, keyMatch.numberOfRanges >= 3 else { return }
                                textStorage.addAttribute(.foregroundColor, value: Theme.headingColor, range: keyMatch.range(at: 1))
                                textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: keyMatch.range(at: 2))
                            }
                        }
                    }
                }
            }
        }

        cachedProtectedRanges = protectedRanges

        textStorage.endEditing()

        let elapsed = (CACurrentMediaTime() - startTime) * 1000
        let tag = caller.isEmpty ? "" : "(\(caller))"
        DiagnosticLog.log("highlightAll\(tag): \(textStorage.length) chars in \(Int(elapsed))ms")
    }

    // MARK: - Incremental Highlighting

    /// Block-level delimiters that can change the meaning of everything below them.
    /// If the edited region contains one, fall back to full re-highlight.
    private static let blockDelimiterRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "^(`{3,}|\\${2}|---\\s*$)", options: .anchorsMatchLines
    )

    /// Re-highlight only the region around the edit, expanded to paragraph boundaries.
    /// Falls back to highlightAll if the edit touches a block delimiter (```, $$, ---).
    func highlightAround(_ textStorage: NSTextStorage, editedRange: NSRange, replacementLength: Int, caller: String = "") {
        guard !isHighlighting else { return }

        let text = textStorage.string
        let nsText = text as NSString

        // Compute the post-edit affected range and expand to paragraph boundaries
        let postEditRange = NSRange(location: editedRange.location, length: replacementLength)
        let paragraphRange = nsText.paragraphRange(for: postEditRange)

        // If the edited paragraph contains a block delimiter, the change could affect
        // everything below (opening/closing a code block or math block). Full re-highlight.
        let paragraphText = nsText.substring(with: paragraphRange)
        if Self.blockDelimiterRegex?.firstMatch(in: paragraphText, range: NSRange(location: 0, length: (paragraphText as NSString).length)) != nil {
            highlightAll(textStorage, caller: caller + "-blockDelim")
            return
        }

        isHighlighting = true
        defer { isHighlighting = false }
        let startTime = CACurrentMediaTime()

        textStorage.beginEditing()

        // Reset attributes in the affected range
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Theme.editorLineHeight
        paragraph.maximumLineHeight = Theme.editorLineHeight

        textStorage.addAttributes([
            .font: Theme.editorFont,
            .foregroundColor: Theme.textColor,
            .paragraphStyle: paragraph,
            .baselineOffset: Theme.editorBaselineOffset
        ], range: paragraphRange)
        textStorage.removeAttribute(.backgroundColor, range: paragraphRange)
        textStorage.removeAttribute(.strikethroughStyle, range: paragraphRange)

        // Adjust cached protected ranges for the edit offset instead of re-scanning
        // the full document. Block delimiter edits already trigger highlightAll which
        // rebuilds the cache from scratch.
        let delta = replacementLength - editedRange.length
        var protectedRanges: [ProtectedRange] = []
        for protectedRange in cachedProtectedRanges {
            let range = protectedRange.range
            if NSMaxRange(range) <= editedRange.location {
                protectedRanges.append(protectedRange)
            } else if range.location >= NSMaxRange(editedRange) {
                protectedRanges.append(ProtectedRange(
                    range: NSRange(location: range.location + delta, length: range.length),
                    kind: protectedRange.kind
                ))
            } else {
                protectedRanges.append(ProtectedRange(
                    range: NSRange(location: range.location, length: max(0, range.length + delta)),
                    kind: protectedRange.kind
                ))
            }
        }
        cachedProtectedRanges = protectedRanges

        // If the paragraph is entirely inside a protected block, apply that block's base style.
        if let block = protectedRanges.first(where: { NSIntersectionRange($0.range, paragraphRange).length == paragraphRange.length }) {
            applyProtectedBlockStyle(block, to: textStorage, range: paragraphRange)
            textStorage.endEditing()
            let elapsed = (CACurrentMediaTime() - startTime) * 1000
            DiagnosticLog.log("highlightAround(\(caller)): inside protected block, \(paragraphRange) in \(Int(elapsed))ms")
            return
        }

        // Run all patterns on the paragraph range only
        for (regex, style) in Self.patterns {
            regex.enumerateMatches(in: text, range: paragraphRange) { match, _, _ in
                guard let match = match else { return }

                if style != .codeBlock && style != .mathBlock && style != .frontmatter {
                    let matchRange = match.range
                    if protectedRanges.contains(where: { NSIntersectionRange($0.range, matchRange).length > 0 }) {
                        return
                    }
                }

                switch style {
                case .heading:
                    if match.numberOfRanges >= 3 {
                        let syntaxRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: syntaxRange)
                        textStorage.addAttributes([
                            .foregroundColor: Theme.headingColor,
                            .font: NSFont.monospacedSystemFont(ofSize: Theme.editorFontSize + 4, weight: .bold)
                        ], range: contentRange)
                    }

                case .bold:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttributes([
                            .foregroundColor: Theme.boldColor,
                            .font: NSFont.monospacedSystemFont(ofSize: Theme.editorFontSize, weight: .bold)
                        ], range: contentRange)
                    }

                case .boldItalic:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        let boldItalicFont = NSFontManager.shared.convert(
                            NSFont.monospacedSystemFont(ofSize: Theme.editorFontSize, weight: .bold),
                            toHaveTrait: .italicFontMask
                        )
                        textStorage.addAttributes([
                            .foregroundColor: Theme.boldColor,
                            .font: boldItalicFont
                        ], range: contentRange)
                    }

                case .italic:
                    if match.numberOfRanges >= 3 {
                        let syntaxRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: syntaxRange)
                        let closingStart = match.range(at: 2).upperBound
                        let closingRange = NSRange(location: closingStart, length: match.range(at: 1).length)
                        if closingRange.upperBound <= textStorage.length {
                            textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: closingRange)
                        }
                        let italicFont = NSFontManager.shared.convert(Theme.editorFont, toHaveTrait: .italicFontMask)
                        textStorage.addAttributes([
                            .foregroundColor: Theme.italicColor,
                            .font: italicFont
                        ], range: contentRange)
                    }

                case .strikethrough:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttributes([
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                            .foregroundColor: Theme.syntaxColor
                        ], range: contentRange)
                    }

                case .inlineCode:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.codeColor, range: contentRange)
                    }

                case .codeBlock:
                    // Code blocks are multi-line; handled via full-document scan above.
                    // Within the paragraph range, a partial code block match means
                    // we're at a fence line — color it as code.
                    textStorage.addAttribute(.foregroundColor, value: Theme.codeColor, range: match.range)
                    if match.numberOfRanges >= 2 {
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: match.range(at: 1))
                    }

                case .link:
                    if match.numberOfRanges >= 4 {
                        let bracketRange = match.range(at: 1)
                        let textRange = match.range(at: 2)
                        let urlPartRange = match.range(at: 3)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: bracketRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.linkColor, range: textRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: urlPartRange)
                    }

                case .blockquote:
                    if match.numberOfRanges >= 3 {
                        let markerRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: markerRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.blockquoteColor, range: contentRange)
                    }

                case .listMarker:
                    textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: match.range)

                case .syntax:
                    textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: match.range)

                case .mathBlock:
                    // Multi-line; skip in incremental mode (handled by blockDelimiter check)
                    break

                case .mathInline:
                    if match.numberOfRanges >= 2 {
                        let contentRange = match.range(at: 1)
                        let openRange = NSRange(location: match.range.location, length: 1)
                        let closeRange = NSRange(location: match.range.location + match.range.length - 1, length: 1)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.mathColor, range: contentRange)
                    }

                case .highlight:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttributes([
                            .foregroundColor: Theme.highlightColor,
                            .backgroundColor: Theme.highlightBackgroundColor
                        ], range: contentRange)
                    }

                case .footnote:
                    textStorage.addAttribute(.foregroundColor, value: Theme.footnoteColor, range: match.range)

                case .wikiLink:
                    if match.numberOfRanges >= 4 {
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: match.range(at: 1))
                        textStorage.addAttribute(.foregroundColor, value: Theme.wikiLinkColor, range: match.range(at: 2))
                        textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: match.range(at: 3))
                    }

                case .htmlTag:
                    textStorage.addAttribute(.foregroundColor, value: Theme.htmlTagColor, range: match.range)

                case .frontmatter:
                    // Multi-line; skip in incremental mode
                    break
                }
            }
        }

        textStorage.endEditing()

        let elapsed = (CACurrentMediaTime() - startTime) * 1000
        DiagnosticLog.log("highlightAround(\(caller)): \(paragraphRange) in \(Int(elapsed))ms")
    }

    // MARK: - Public Query

    /// Returns true if the given character position is inside a code block, math block, or frontmatter.
    func isInsideProtectedRange(at position: Int) -> Bool {
        cachedProtectedRanges.contains { NSLocationInRange(position, $0.range) }
    }

    private func applyProtectedBlockStyle(_ block: ProtectedRange, to textStorage: NSTextStorage, range: NSRange) {
        switch block.kind {
        case .code:
            textStorage.addAttribute(.foregroundColor, value: Theme.codeColor, range: range)

        case .math:
            textStorage.addAttribute(.foregroundColor, value: Theme.mathColor, range: range)

        case .frontmatter:
            textStorage.addAttribute(.foregroundColor, value: Theme.frontmatterColor, range: range)
            guard let keyRegex = Self.frontmatterKeyRegex else { return }
            keyRegex.enumerateMatches(in: textStorage.string, range: range) { match, _, _ in
                guard let match, match.numberOfRanges >= 3 else { return }
                textStorage.addAttribute(.foregroundColor, value: Theme.headingColor, range: match.range(at: 1))
                textStorage.addAttribute(.foregroundColor, value: Theme.syntaxColor, range: match.range(at: 2))
            }
        }
    }
}
