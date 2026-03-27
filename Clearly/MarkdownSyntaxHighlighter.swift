import AppKit
import os

final class MarkdownSyntaxHighlighter: NSObject, NSTextStorageDelegate {

    private var isHighlighting = false

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
        add("(?<!\\$)\\$(?!\\$)(.+?)(?<!\\$)\\$(?!\\$)", .mathInline)

        // Headings: # Heading
        add("^(#{1,6}\\s+)(.+)$", .heading, options: .anchorsMatchLines)

        // Bold: **text** or __text__
        add("(\\*\\*|__)(.+?)(\\1)", .bold)

        // Italic: *text* or _text_ (not inside words for _)
        add("(?<![\\w*])(\\*|_)(?!\\s)(.+?)(?<!\\s)\\1(?![\\w*])", .italic)

        // Strikethrough: ~~text~~
        add("(~~)(.+?)(~~)", .strikethrough)

        // Inline code: `code`
        add("(`+)(.+?)(\\1)", .inlineCode)

        // Links: [text](url)
        add("(\\[)(.+?)(\\]\\(.+?\\))", .link)

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

        return result
    }()

    // MARK: - Highlight Styles

    private enum HighlightStyle {
        case heading
        case bold
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
    }

    // MARK: - NSTextStorageDelegate

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        highlightAll(textStorage)
    }

    // MARK: - Highlighting

    func highlightAll(_ textStorage: NSTextStorage) {
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
        var codeBlockRanges: [NSRange] = []

        for (regex, style) in Self.patterns {
            regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let match = match else { return }

                // If this isn't a code/math/frontmatter block pattern, skip if inside a protected block
                if style != .codeBlock && style != .mathBlock && style != .frontmatter {
                    let matchRange = match.range
                    if codeBlockRanges.contains(where: { NSIntersectionRange($0, matchRange).length > 0 }) {
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
                    codeBlockRanges.append(match.range)
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
                    codeBlockRanges.append(match.range)
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

                case .frontmatter:
                    let matchedText = (text as NSString).substring(with: match.range)
                    guard FrontmatterSupport.extract(from: matchedText) != nil else { return }
                    codeBlockRanges.append(match.range)
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

        textStorage.endEditing()

        let elapsed = (CACurrentMediaTime() - startTime) * 1000
        DiagnosticLog.log("highlightAll: \(textStorage.length) chars in \(Int(elapsed))ms")
    }
}
