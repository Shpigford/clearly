import AppKit

final class MarkdownSyntaxHighlighter: NSObject, NSTextStorageDelegate {

    // MARK: - Regex Patterns

    private static let patterns: [(NSRegularExpression, HighlightStyle)] = {
        var result: [(NSRegularExpression, HighlightStyle)] = []

        func add(_ pattern: String, _ style: HighlightStyle, options: NSRegularExpression.Options = []) {
            if let regex = try? NSRegularExpression(pattern: pattern, options: options) {
                result.append((regex, style))
            }
        }

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
        let fullRange = NSRange(location: 0, length: textStorage.length)
        let text = textStorage.string

        // Reset to default style
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = Theme.lineSpacing

        textStorage.addAttributes([
            .font: Theme.editorFont,
            .foregroundColor: Theme.textColor,
            .paragraphStyle: paragraph
        ], range: fullRange)

        // Track code block ranges to skip inner highlighting
        var codeBlockRanges: [NSRange] = []

        for (regex, style) in Self.patterns {
            regex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
                guard let match = match else { return }

                // If this isn't a code/math block pattern, skip if inside a protected block
                if style != .codeBlock && style != .mathBlock {
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
                }
            }
        }
    }
}
