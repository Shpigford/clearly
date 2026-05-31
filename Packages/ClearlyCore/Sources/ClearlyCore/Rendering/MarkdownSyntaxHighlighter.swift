import CoreText
import Foundation
import os
import QuartzCore

private typealias Attr = PlatformTextAttributes

/// A soft-wrap indent length parsed from frontmatter (`wrapIndent` / `firstLineIndent`).
/// Carries an explicit CSS-style unit so the editor and the preview stay in sync:
/// the editor resolves it to points, the preview emits it verbatim as CSS.
public struct IndentLength: Equatable, Sendable {
    public enum Unit: String, Sendable {
        case em, ch, px, pt
    }

    public let value: CGFloat
    public let unit: Unit

    public init(value: CGFloat, unit: Unit) {
        self.value = value
        self.unit = unit
    }

    /// Parse a frontmatter value like `2em`, `2ch`, `20px`, `20pt`, or a bare
    /// number (defaults to `em`). Returns `nil` for empty, negative, or
    /// unparseable input.
    public static func parse(_ raw: String) -> IndentLength? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        var unit: Unit = .em
        var numberPart = trimmed
        for candidate in [Unit.em, .ch, .px, .pt] where trimmed.hasSuffix(candidate.rawValue) {
            unit = candidate
            numberPart = String(trimmed.dropLast(candidate.rawValue.count))
            break
        }
        guard let value = Double(numberPart.trimmingCharacters(in: .whitespaces)), value >= 0 else {
            return nil
        }
        return IndentLength(value: CGFloat(value), unit: unit)
    }

    /// Resolve to points for the editor's `NSParagraphStyle`. `em` scales with the
    /// editor font size, `ch` with the monospaced character advance; `px`/`pt` are
    /// already absolute.
    public func points(fontSize: CGFloat, characterWidth: CGFloat) -> CGFloat {
        switch unit {
        case .em: return value * fontSize
        case .ch: return value * characterWidth
        case .px, .pt: return value
        }
    }

    /// The CSS length string, e.g. `2em`, `-4px`. Whole numbers drop the `.0`.
    public var css: String {
        "\(String(format: "%g", Double(value)))\(unit.rawValue)"
    }
}

public final class MarkdownSyntaxHighlighter: NSObject {

    public override init() {
        super.init()
    }

    private var isHighlighting = false
    private var cachedProtectedRanges: [ProtectedRange] = []

    /// Set by `highlightAround` when a block delimiter is detected.
    /// The caller should schedule a deferred `highlightAll` instead of running it synchronously.
    public var needsFullHighlight = false

    // MARK: - Soft-wrap indent (frontmatter `wrapIndent` / `firstLineIndent`)

    /// Frontmatter key for the soft-wrapped continuation-line indent.
    public static let wrapIndentKey = "wrapIndent"
    /// Frontmatter key for the first-line indent.
    public static let firstLineIndentKey = "firstLineIndent"
    /// Layout-directive frontmatter keys: consumed for rendering, not content
    /// metadata. The preview hides these from its frontmatter block.
    public static let layoutFrontmatterKeys: Set<String> = [wrapIndentKey, firstLineIndentKey]

    /// Resolved indent for the current document, or `nil` when the feature is off.
    /// `head` maps to `headIndent` (soft-wrapped continuation lines); `firstLine`
    /// maps to `firstLineHeadIndent` (first line of each hard-break-bounded paragraph).
    private var cachedIndent: (head: IndentLength, firstLine: IndentLength)?
    /// Last-recorded UTF-16 length of the frontmatter region (may be stale after an
    /// edit, until the next refresh), used to decide whether an incremental edit
    /// could have changed the indent config.
    private var cachedFrontmatterLength: Int = 0

    /// Whether a non-zero indent is active for the current document.
    private var isIndentActive: Bool {
        guard let indent = cachedIndent else { return false }
        return indent.head.value > 0 || indent.firstLine.value > 0
    }

    /// Parse soft-wrap indent settings from a document's YAML frontmatter.
    /// Returns `nil` (feature off) when there is no frontmatter, neither
    /// `wrapIndent` nor `firstLineIndent` is present, or both keys are
    /// unparseable. Each value may carry an explicit unit (`em`, `ch`, `px`,
    /// `pt`); a bare number defaults to `em`.
    public static func indentValues(from text: String) -> (head: IndentLength, firstLine: IndentLength)? {
        guard let block = FrontmatterSupport.extract(from: text) else { return nil }
        return indentValues(fromFields: block.fields)
    }

    private static func indentValues(fromFields fields: [FrontmatterSupport.Field]) -> (head: IndentLength, firstLine: IndentLength)? {
        var head: IndentLength?
        var firstLine: IndentLength?
        for field in fields {
            switch field.key {
            case Self.wrapIndentKey:
                if let parsed = IndentLength.parse(field.value) { head = parsed }
            case Self.firstLineIndentKey:
                if let parsed = IndentLength.parse(field.value) { firstLine = parsed }
            default:
                break
            }
        }
        if head == nil && firstLine == nil { return nil }
        let zero = IndentLength(value: 0, unit: .em)
        return (head ?? zero, firstLine ?? zero)
    }

    /// Re-read the indent config from `text`. When `markNeedsFullHighlight` is true
    /// and the resolved values changed, request a deferred full re-highlight so the
    /// whole document picks up the new indent (an incremental pass only restyles the
    /// edited paragraph).
    private func refreshIndentCache(from text: String, markNeedsFullHighlight: Bool) {
        let old = cachedIndent
        if let block = FrontmatterSupport.extract(from: text) {
            // Always record the frontmatter span — even when no indent keys are
            // present yet — so that adding the keys later counts as an in-region
            // edit and triggers a re-highlight without needing to reopen the file.
            cachedFrontmatterLength = Self.frontmatterRegionLength(of: text, block: block)
            cachedIndent = Self.indentValues(fromFields: block.fields)
        } else if case let structuralLength = Self.structuralFrontmatterRegionLength(of: text), structuralLength > 0 {
            // A leading `--- ... ---` block still exists but a line doesn't parse as
            // a field yet (e.g. a key that's been typed but has no colon yet). Keep
            // the last-known indent and the region length so a transient unparseable
            // state doesn't drop the body indent, and so edits stay in-region long
            // enough to refresh once the line becomes valid again.
            cachedFrontmatterLength = structuralLength
        } else {
            cachedIndent = nil
            cachedFrontmatterLength = 0
        }
        if markNeedsFullHighlight && Self.indentChanged(old, cachedIndent) {
            needsFullHighlight = true
        }
    }

    /// Tuples can't be `Equatable`, so compare the optional indent pair by hand.
    private static func indentChanged(
        _ lhs: (head: IndentLength, firstLine: IndentLength)?,
        _ rhs: (head: IndentLength, firstLine: IndentLength)?
    ) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return false
        case let (a?, b?): return a.head != b.head || a.firstLine != b.firstLine
        default: return true
        }
    }

    /// UTF-16 length of the leading frontmatter region (including delimiters),
    /// or 0 when there is no frontmatter. Used to decide whether an incremental
    /// edit could have changed the indent config. Computed independently of which
    /// keys are present, so adding indent keys to existing frontmatter still
    /// registers as an in-region edit.
    static func frontmatterRegionLength(of text: String) -> Int {
        guard let block = FrontmatterSupport.extract(from: text) else { return 0 }
        return frontmatterRegionLength(of: text, block: block)
    }

    private static func frontmatterRegionLength(of text: String, block: FrontmatterSupport.Block) -> Int {
        max(0, (text as NSString).length - (block.body as NSString).length)
    }

    /// UTF-16 length of the leading `--- ... ---` block detected by delimiters alone,
    /// ignoring whether the body parses as fields. 0 when there's no such block.
    /// Used to keep the indent cache alive while a frontmatter line is mid-edit and
    /// `FrontmatterSupport.extract` transiently fails.
    static func structuralFrontmatterRegionLength(of text: String) -> Int {
        guard let regex = frontmatterBlockRegex else { return 0 }
        let ns = text as NSString
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))?.range.length ?? 0
    }

    /// The editor paragraph style: line height (always) plus soft-wrap indent when active.
    /// `headIndent` indents soft-wrapped continuation lines; `firstLineHeadIndent`
    /// indents the first line of each (hard-break-bounded) paragraph.
    private func indentParagraphStyle() -> PlatformParagraphStyle {
        let paragraph = PlatformParagraphStyle()
        paragraph.minimumLineHeight = Theme.editorLineHeight
        paragraph.maximumLineHeight = Theme.editorLineHeight
        if let indent = cachedIndent, isIndentActive {
            let fontSize = Theme.editorFontSize
            let charWidth = Self.characterWidth(of: Theme.editorFont)
            paragraph.headIndent = indent.head.points(fontSize: fontSize, characterWidth: charWidth)
            paragraph.firstLineHeadIndent = indent.firstLine.points(fontSize: fontSize, characterWidth: charWidth)
        }
        return paragraph
    }

    /// Advance width of one character in `font`. The editor font is monospaced,
    /// so a single space measures the column width used for indent math.
    private static func characterWidth(of font: PlatformFont) -> CGFloat {
        let ctFont = font as CTFont
        var character: UniChar = 0x20 // space
        var glyph = CGGlyph(0)
        guard CTFontGetGlyphsForCharacters(ctFont, &character, &glyph, 1) else {
            return font.pointSize * 0.6
        }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyph, &advance, 1)
        return advance.width > 0 ? advance.width : font.pointSize * 0.6
    }

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
        add(MathSupport.inlineMathPattern, .mathInline)

        // Headings: # Heading
        add("^(#{1,6}\\s+)(.+)$", .heading, options: .anchorsMatchLines)

        // Bold italic: ***text*** or ___text___
        add("(\\*\\*\\*|___)([^\n]+?)(\\1)", .boldItalic)

        // Bold: **text** or __text__ (not part of ***triple***)
        add("(?<![*_])(\\*\\*(?!\\*)|__(?!_))([^\n]+?)(\\1)(?![*_])", .bold)

        // Italic: *text* or _text_ (not inside words for _)
        add("(?<![\\w*])(\\*(?!\\*)|_(?!_))(?!\\s)([^\n]+?)(?<!\\s)\\1(?![\\w*])", .italic)

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
        guard textStorage.length <= Limits.maxHighlightAllLength else {
            DiagnosticLog.log("MarkdownSyntaxHighlighter: skipping highlightAll over \(textStorage.length) chars")
            return
        }
        isHighlighting = true
        defer { isHighlighting = false }
        let startTime = CACurrentMediaTime()

        textStorage.beginEditing()
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let text = textStorage.string

        // Refresh soft-wrap indent config from frontmatter before styling the document.
        refreshIndentCache(from: text, markNeedsFullHighlight: false)

        // Reset to default style
        let paragraph = indentParagraphStyle()

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

                case .htmlTag:
                    textStorage.addAttribute(Attr.foregroundColor, value: Theme.htmlTagColor, range: match.range)

                case .frontmatter:
                    // The block regex is anchored at the document start and requires
                    // `--- ... ---`, so a match is structurally frontmatter even when a
                    // line is mid-edit and doesn't yet parse as a field. Color the region
                    // regardless; the field-level key coloring below is best-effort.
                    // (Gating this on a full parse made the whole block lose its
                    // highlight while a new field line was being typed.)
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
            // Treat any document-leading `--- ... ---` block as frontmatter for
            // protection, without requiring a full field parse — otherwise a
            // half-typed field line would drop the block's protected status.
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

        // Compute the post-edit affected range and expand to paragraph boundaries.
        // iOS predictive text / marked-text composition can fire textViewDidChange
        // without a matching shouldChangeTextIn, so the cached editedRange may no
        // longer fit the live string. Validate before calling paragraphRange, which
        // throws NSRangeException on out-of-bounds input.
        let textLength = nsText.length
        let safeLocation = max(0, min(editedRange.location, textLength))
        let safeLength = max(0, min(replacementLength, textLength - safeLocation))
        if safeLocation != editedRange.location || safeLength != replacementLength {
            highlightAll(textStorage, caller: "\(caller)-stale-range")
            return
        }
        let postEditRange = NSRange(location: safeLocation, length: safeLength)
        let paragraphRange = nsText.paragraphRange(for: postEditRange)

        // If the edit could lie inside the frontmatter region, re-read the indent
        // config. A changed value flips `needsFullHighlight` so the whole document
        // restyles; edits in the body reuse the cached values for free.
        // `cachedFrontmatterLength` reflects the pre-edit text, so allow a little
        // slack past it to catch edits that land right at the old boundary.
        if editedRange.location <= cachedFrontmatterLength + 8 {
            refreshIndentCache(from: text, markNeedsFullHighlight: true)
        }

        // A "paragraph" here is a `\n`-bounded run. A file with no newlines (binary blob,
        // pasted log dump) is one paragraph the size of the whole file — running the regex
        // pipeline over multi-MB input is the catastrophic case. Bail; the file-size cap on
        // open already keeps these out of the editor in normal use.
        guard paragraphRange.length <= Limits.maxHighlightAllLength else {
            DiagnosticLog.log("MarkdownSyntaxHighlighter: skipping highlightAround over \(paragraphRange.length)-char paragraph")
            return
        }

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
            textStorage.addAttributes([
                Attr.font: Theme.editorFont,
                Attr.paragraphStyle: indentParagraphStyle(),
                Attr.baselineOffset: Theme.editorBaselineOffset
            ], range: paragraphRange)
        } else if isIndentActive {
            // Soft-wrap indent is active. Typing only stamps the line-height typing
            // attributes onto new characters, so re-apply the indent paragraph style
            // here to keep plain paragraphs aligned.
            textStorage.addAttribute(Attr.paragraphStyle, value: indentParagraphStyle(), range: paragraphRange)
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
