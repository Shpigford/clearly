import Foundation
import os
import QuartzCore

private typealias Attr = PlatformTextAttributes

public final class MarkdownSyntaxHighlighter: NSObject {

    public override init() {
        super.init()
    }

    private var isHighlighting = false
    private var cachedProtectedRanges: [ProtectedRange] = []

    /// Set by `highlightAround` when a block delimiter is detected.
    /// The caller should schedule a deferred `highlightAll` instead of running it synchronously.
    public var needsFullHighlight = false

    // MARK: - Regex Patterns

    private static let frontmatterKeyRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "^([\\w][\\w\\s.-]*)(:)",
        options: .anchorsMatchLines
    )

    private static let frontmatterBlockRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "\\A---[ \\t]*\\n([\\s\\S]*?)\\n---[ \\t]*(?:\\n|\\z)"
    )

    private static let fencedCodeBlockRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "^(`{3,})(.*?)\\n([\\s\\S]*?)^\\1\\s*$",
        options: .anchorsMatchLines
    )

    private static let displayMathBlockRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: "^\\$\\$\\n([\\s\\S]*?)^\\$\\$\\s*$",
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
        if let regex = frontmatterBlockRegex {
            result.append((regex, .frontmatter))
        }

        // Fenced code blocks (``` ... ```) — must come first to prevent inner highlighting
        if let regex = fencedCodeBlockRegex {
            result.append((regex, .codeBlock))
        }

        // Display math blocks: $$...$$ (multiline)
        if let regex = displayMathBlockRegex {
            result.append((regex, .mathBlock))
        }

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

        // Tags: #tag (not headings, not inside code blocks)
        add(#"(?:^|(?<=\s))#([\p{L}\p{N}_\-/]*[\p{L}_\-/][\p{L}\p{N}_\-/]*)"#, .tag)

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
        case tag
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

    public func highlightAll(_ textStorage: PlatformTextStorage, caller: String = "") {
        guard !isHighlighting else { return }
        isHighlighting = true
        defer { isHighlighting = false }
        let startTime = CACurrentMediaTime()

        textStorage.beginEditing()
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let text = textStorage.string

        // Reset to default style
        let paragraph = PlatformParagraphStyle()
        paragraph.minimumLineHeight = Theme.editorLineHeight
        paragraph.maximumLineHeight = Theme.editorLineHeight

        textStorage.addAttributes([
            Attr.font: Theme.editorFont,
            Attr.foregroundColor: Theme.textColor,
            Attr.paragraphStyle: paragraph,
            Attr.baselineOffset: Theme.editorBaselineOffset
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
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: syntaxRange)
                        textStorage.addAttributes([
                            Attr.foregroundColor: Theme.headingColor,
                            Attr.font: PlatformFont.clearlyMonospacedSystemFont(ofSize: Theme.editorFontSize + 4, weight: .bold)
                        ], range: contentRange)
                    }

                case .bold:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttributes([
                            Attr.foregroundColor: Theme.boldColor,
                            Attr.font: PlatformFont.clearlyMonospacedSystemFont(ofSize: Theme.editorFontSize, weight: .bold)
                        ], range: contentRange)
                    }

                case .boldItalic:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        let boldItalicFont = PlatformFont.clearlyMonospacedBoldItalic(size: Theme.editorFontSize)
                        textStorage.addAttributes([
                            Attr.foregroundColor: Theme.boldColor,
                            Attr.font: boldItalicFont
                        ], range: contentRange)
                    }

                case .italic:
                    if match.numberOfRanges >= 3 {
                        let syntaxRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: syntaxRange)
                        // Apply to the closing marker too
                        let closingStart = match.range(at: 2).upperBound
                        let closingRange = NSRange(location: closingStart, length: match.range(at: 1).length)
                        if closingRange.upperBound <= textStorage.length {
                            textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closingRange)
                        }
                        let italicFont = Theme.editorFont.withItalicTrait()
                        textStorage.addAttributes([
                            Attr.foregroundColor: Theme.italicColor,
                            Attr.font: italicFont
                        ], range: contentRange)
                    }

                case .strikethrough:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttributes([
                            Attr.strikethroughStyle: Attr.singleUnderlineStyleValue,
                            Attr.foregroundColor: Theme.syntaxColor
                        ], range: contentRange)
                    }

                case .inlineCode:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.codeColor, range: contentRange)
                    }

                case .codeBlock:
                    protectedRanges.append(ProtectedRange(range: match.range, kind: .code))
                    // Fade the entire block
                    textStorage.addAttribute(Attr.foregroundColor, value: Theme.codeColor, range: match.range)
                    // Fade the fences specifically
                    if match.numberOfRanges >= 2 {
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: match.range(at: 1))
                    }

                case .link:
                    if match.numberOfRanges >= 4 {
                        let bracketRange = match.range(at: 1)
                        let textRange = match.range(at: 2)
                        let urlPartRange = match.range(at: 3)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: bracketRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.linkColor, range: textRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: urlPartRange)
                    }

                case .blockquote:
                    if match.numberOfRanges >= 3 {
                        let markerRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: markerRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.blockquoteColor, range: contentRange)
                    }

                case .listMarker:
                    textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: match.range)

                case .syntax:
                    textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: match.range)

                case .mathBlock:
                    protectedRanges.append(ProtectedRange(range: match.range, kind: .math))
                    textStorage.addAttribute(Attr.foregroundColor, value: Theme.mathColor, range: match.range)
                    // Fade the opening $$ delimiter
                    let openRange = NSRange(location: match.range.location, length: 2)
                    if openRange.upperBound <= textStorage.length {
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: openRange)
                    }
                    // Fade the closing $$ delimiter
                    let closeStart = match.range.location + match.range.length - 2
                    let closeRange = NSRange(location: closeStart, length: 2)
                    if closeRange.upperBound <= textStorage.length && closeStart >= match.range.location {
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                    }

                case .mathInline:
                    if match.numberOfRanges >= 2 {
                        let contentRange = match.range(at: 1)
                        let openRange = NSRange(location: match.range.location, length: 1)
                        let closeRange = NSRange(location: match.range.location + match.range.length - 1, length: 1)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.mathColor, range: contentRange)
                    }

                case .highlight:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttributes([
                            Attr.foregroundColor: Theme.highlightColor,
                            Attr.backgroundColor: Theme.highlightBackgroundColor
                        ], range: contentRange)
                    }

                case .footnote:
                    textStorage.addAttribute(Attr.foregroundColor, value: Theme.footnoteColor, range: match.range)

                case .wikiLink:
                    if match.numberOfRanges >= 4 {
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: match.range(at: 1))
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.wikiLinkColor, range: match.range(at: 2))
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: match.range(at: 3))
                    }

                case .tag:
                    let hashRange = NSRange(location: match.range.location, length: 1)
                    textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: hashRange)
                    if match.numberOfRanges >= 2 {
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.tagColor, range: match.range(at: 1))
                    }

                case .htmlTag:
                    textStorage.addAttribute(Attr.foregroundColor, value: Theme.htmlTagColor, range: match.range)

                case .frontmatter:
                    let matchedText = (text as NSString).substring(with: match.range)
                    guard FrontmatterSupport.extract(from: matchedText) != nil else { return }
                    protectedRanges.append(ProtectedRange(range: match.range, kind: .frontmatter))
                    let nsText = text as NSString
                    // Base color for the whole block
                    textStorage.addAttribute(Attr.foregroundColor, value: Theme.frontmatterColor, range: match.range)
                    // Color the opening --- delimiter line
                    let openLineEnd = nsText.range(of: "\n", range: NSRange(location: match.range.location, length: match.range.length))
                    if openLineEnd.location != NSNotFound {
                        let openRange = NSRange(location: match.range.location, length: openLineEnd.location - match.range.location)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: openRange)
                    }
                    // Color the closing --- delimiter (last line of match)
                    let matchStr = nsText.substring(with: match.range) as NSString
                    let lastNewline = matchStr.range(of: "\n", options: .backwards)
                    if lastNewline.location != NSNotFound {
                        let closeStart = match.range.location + lastNewline.location + 1
                        let closeLen = match.range.location + match.range.length - closeStart
                        if closeLen > 0 {
                            let closeRange = NSRange(location: closeStart, length: closeLen)
                            textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        }
                    }
                    // Color YAML keys within the body (group 1)
                    if match.numberOfRanges >= 2 {
                        let bodyRange = match.range(at: 1)
                        if bodyRange.location != NSNotFound, let keyRegex = Self.frontmatterKeyRegex {
                            keyRegex.enumerateMatches(in: text, range: bodyRange) { keyMatch, _, _ in
                                guard let keyMatch = keyMatch, keyMatch.numberOfRanges >= 3 else { return }
                                textStorage.addAttribute(Attr.foregroundColor, value: Theme.headingColor, range: keyMatch.range(at: 1))
                                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: keyMatch.range(at: 2))
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

    private func rebuildProtectedRanges(for text: String) -> [ProtectedRange] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var protectedRanges: [ProtectedRange] = []

        Self.frontmatterBlockRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let matchedText = nsText.substring(with: match.range)
            guard FrontmatterSupport.extract(from: matchedText) != nil else { return }
            protectedRanges.append(ProtectedRange(range: match.range, kind: .frontmatter))
        }

        Self.fencedCodeBlockRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            protectedRanges.append(ProtectedRange(range: match.range, kind: .code))
        }

        Self.displayMathBlockRegex?.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            protectedRanges.append(ProtectedRange(range: match.range, kind: .math))
        }

        protectedRanges.sort { lhs, rhs in
            lhs.range.location < rhs.range.location
        }
        return protectedRanges
    }

    /// Re-highlight only the region around the edit, expanded to paragraph boundaries.
    /// Falls back to highlightAll if the edit touches a block delimiter (```, $$, ---).
    public func highlightAround(_ textStorage: PlatformTextStorage, editedRange: NSRange, replacementLength: Int, caller: String = "") {
        guard !isHighlighting else { return }

        let text = textStorage.string
        let nsText = text as NSString

        // Compute the post-edit affected range and expand to paragraph boundaries
        let postEditRange = NSRange(location: editedRange.location, length: replacementLength)
        let paragraphRange = nsText.paragraphRange(for: postEditRange)

        // If the edited paragraph contains a block delimiter, the change could affect
        // everything below (opening/closing a code block or math block). Signal the caller
        // to schedule a deferred full re-highlight, but still highlight the current paragraph
        // immediately for responsive feedback.
        let paragraphText = nsText.substring(with: paragraphRange)
        let editedBlockDelimiter = Self.blockDelimiterRegex?.firstMatch(
            in: paragraphText,
            range: NSRange(location: 0, length: (paragraphText as NSString).length)
        ) != nil
        if editedBlockDelimiter {
            needsFullHighlight = true
        }

        isHighlighting = true
        defer { isHighlighting = false }
        let startTime = CACurrentMediaTime()

        textStorage.beginEditing()

        // Reset attributes in the affected range. Only reset font/paragraph/baseline
        // when the range actually has non-default fonts (headings, code, bold, italic).
        // Skipping the font reset for plain text avoids glyph regeneration, which is
        // the main per-keystroke cost on large documents.
        var needsFontReset = false
        textStorage.enumerateAttribute(Attr.font, in: paragraphRange, options: .longestEffectiveRangeNotRequired) { value, _, stop in
            if let font = value as? PlatformFont, font != Theme.editorFont {
                needsFontReset = true
                stop.pointee = true
            }
        }

        if needsFontReset {
            let paragraph = PlatformParagraphStyle()
            paragraph.minimumLineHeight = Theme.editorLineHeight
            paragraph.maximumLineHeight = Theme.editorLineHeight
            textStorage.addAttributes([
                Attr.font: Theme.editorFont,
                Attr.paragraphStyle: paragraph,
                Attr.baselineOffset: Theme.editorBaselineOffset
            ], range: paragraphRange)
        }
        textStorage.addAttribute(Attr.foregroundColor, value: Theme.textColor, range: paragraphRange)
        textStorage.removeAttribute(Attr.backgroundColor, range: paragraphRange)
        textStorage.removeAttribute(Attr.strikethroughStyle, range: paragraphRange)

        // Keep cached protected ranges aligned with the edit. Most edits can cheaply
        // shift the cached ranges; block delimiters need a full protected-range rescan
        // so semantic queries stay correct until the deferred highlightAll runs.
        let protectedRanges: [ProtectedRange]
        if editedBlockDelimiter {
            // Keep protected-range queries correct until the deferred highlightAll runs.
            protectedRanges = rebuildProtectedRanges(for: text)
        } else {
            let delta = replacementLength - editedRange.length
            var shiftedProtectedRanges: [ProtectedRange] = []
            for protectedRange in cachedProtectedRanges {
                let range = protectedRange.range
                if NSMaxRange(range) <= editedRange.location {
                    shiftedProtectedRanges.append(protectedRange)
                } else if range.location >= NSMaxRange(editedRange) {
                    shiftedProtectedRanges.append(ProtectedRange(
                        range: NSRange(location: range.location + delta, length: range.length),
                        kind: protectedRange.kind
                    ))
                } else {
                    shiftedProtectedRanges.append(ProtectedRange(
                        range: NSRange(location: range.location, length: max(0, range.length + delta)),
                        kind: protectedRange.kind
                    ))
                }
            }
            protectedRanges = shiftedProtectedRanges
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
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: syntaxRange)
                        textStorage.addAttributes([
                            Attr.foregroundColor: Theme.headingColor,
                            Attr.font: PlatformFont.clearlyMonospacedSystemFont(ofSize: Theme.editorFontSize + 4, weight: .bold)
                        ], range: contentRange)
                    }

                case .bold:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttributes([
                            Attr.foregroundColor: Theme.boldColor,
                            Attr.font: PlatformFont.clearlyMonospacedSystemFont(ofSize: Theme.editorFontSize, weight: .bold)
                        ], range: contentRange)
                    }

                case .boldItalic:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        let boldItalicFont = PlatformFont.clearlyMonospacedBoldItalic(size: Theme.editorFontSize)
                        textStorage.addAttributes([
                            Attr.foregroundColor: Theme.boldColor,
                            Attr.font: boldItalicFont
                        ], range: contentRange)
                    }

                case .italic:
                    if match.numberOfRanges >= 3 {
                        let syntaxRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: syntaxRange)
                        let closingStart = match.range(at: 2).upperBound
                        let closingRange = NSRange(location: closingStart, length: match.range(at: 1).length)
                        if closingRange.upperBound <= textStorage.length {
                            textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closingRange)
                        }
                        let italicFont = Theme.editorFont.withItalicTrait()
                        textStorage.addAttributes([
                            Attr.foregroundColor: Theme.italicColor,
                            Attr.font: italicFont
                        ], range: contentRange)
                    }

                case .strikethrough:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttributes([
                            Attr.strikethroughStyle: Attr.singleUnderlineStyleValue,
                            Attr.foregroundColor: Theme.syntaxColor
                        ], range: contentRange)
                    }

                case .inlineCode:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.codeColor, range: contentRange)
                    }

                case .codeBlock:
                    // Code blocks are multi-line; handled via full-document scan above.
                    // Within the paragraph range, a partial code block match means
                    // we're at a fence line — color it as code.
                    textStorage.addAttribute(Attr.foregroundColor, value: Theme.codeColor, range: match.range)
                    if match.numberOfRanges >= 2 {
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: match.range(at: 1))
                    }

                case .link:
                    if match.numberOfRanges >= 4 {
                        let bracketRange = match.range(at: 1)
                        let textRange = match.range(at: 2)
                        let urlPartRange = match.range(at: 3)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: bracketRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.linkColor, range: textRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: urlPartRange)
                    }

                case .blockquote:
                    if match.numberOfRanges >= 3 {
                        let markerRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: markerRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.blockquoteColor, range: contentRange)
                    }

                case .listMarker:
                    textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: match.range)

                case .syntax:
                    textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: match.range)

                case .mathBlock:
                    // Multi-line; skip in incremental mode (handled by blockDelimiter check)
                    break

                case .mathInline:
                    if match.numberOfRanges >= 2 {
                        let contentRange = match.range(at: 1)
                        let openRange = NSRange(location: match.range.location, length: 1)
                        let closeRange = NSRange(location: match.range.location + match.range.length - 1, length: 1)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.mathColor, range: contentRange)
                    }

                case .highlight:
                    if match.numberOfRanges >= 4 {
                        let openRange = match.range(at: 1)
                        let contentRange = match.range(at: 2)
                        let closeRange = match.range(at: 3)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: openRange)
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: closeRange)
                        textStorage.addAttributes([
                            Attr.foregroundColor: Theme.highlightColor,
                            Attr.backgroundColor: Theme.highlightBackgroundColor
                        ], range: contentRange)
                    }

                case .footnote:
                    textStorage.addAttribute(Attr.foregroundColor, value: Theme.footnoteColor, range: match.range)

                case .wikiLink:
                    if match.numberOfRanges >= 4 {
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: match.range(at: 1))
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.wikiLinkColor, range: match.range(at: 2))
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: match.range(at: 3))
                    }

                case .tag:
                    let hashRange = NSRange(location: match.range.location, length: 1)
                    textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: hashRange)
                    if match.numberOfRanges >= 2 {
                        textStorage.addAttribute(Attr.foregroundColor, value: Theme.tagColor, range: match.range(at: 1))
                    }

                case .htmlTag:
                    textStorage.addAttribute(Attr.foregroundColor, value: Theme.htmlTagColor, range: match.range)

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
    public func isInsideProtectedRange(at position: Int) -> Bool {
        cachedProtectedRanges.contains { NSLocationInRange(position, $0.range) }
    }

    private func applyProtectedBlockStyle(_ block: ProtectedRange, to textStorage: PlatformTextStorage, range: NSRange) {
        switch block.kind {
        case .code:
            textStorage.addAttribute(Attr.foregroundColor, value: Theme.codeColor, range: range)

        case .math:
            textStorage.addAttribute(Attr.foregroundColor, value: Theme.mathColor, range: range)

        case .frontmatter:
            textStorage.addAttribute(Attr.foregroundColor, value: Theme.frontmatterColor, range: range)
            guard let keyRegex = Self.frontmatterKeyRegex else { return }
            keyRegex.enumerateMatches(in: textStorage.string, range: range) { match, _, _ in
                guard let match, match.numberOfRanges >= 3 else { return }
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.headingColor, range: match.range(at: 1))
                textStorage.addAttribute(Attr.foregroundColor, value: Theme.syntaxColor, range: match.range(at: 2))
            }
        }
    }
}
