import Foundation

struct HeadingItem: Identifiable, Hashable {
    let id = UUID()
    let level: Int       // 1-6
    let title: String    // Inline markdown stripped
    let range: NSRange   // Location in document text
    let previewAnchor: PreviewSourceAnchor
}

final class OutlineState: ObservableObject {
    @Published var isVisible: Bool {
        didSet { UserDefaults.standard.set(isVisible, forKey: "outlineVisible") }
    }
    @Published var headings: [HeadingItem] = []

    /// Set by EditorView coordinator, called when user clicks a heading (editor scroll)
    var scrollToRange: ((NSRange) -> Void)?
    /// Set by PreviewView coordinator, called when user clicks a heading (preview scroll)
    var scrollToPreviewAnchor: ((PreviewSourceAnchor) -> Void)?

    private static let atxHeadingRegex = try! NSRegularExpression(
        pattern: "^(#{1,6})\\s+(.+)$",
        options: .anchorsMatchLines
    )
    private static let setextHeadingRegex = try! NSRegularExpression(
        pattern: "^(.+)\\n([=-]+)[ \\t]*$",
        options: .anchorsMatchLines
    )
    private static let codeBlockRegex = try! NSRegularExpression(
        pattern: "^(`{3,})(.*?)\\n([\\s\\S]*?)^\\1\\s*$",
        options: [.anchorsMatchLines]
    )
    private static let frontmatterRegex = try! NSRegularExpression(
        pattern: "\\A---[ \\t]*\\n([\\s\\S]*?)\\n---[ \\t]*(?:\\n|\\z)",
        options: []
    )

    init() {
        self.isVisible = UserDefaults.standard.bool(forKey: "outlineVisible")
    }

    func toggle() {
        isVisible.toggle()
    }

    func parseHeadings(from text: String) {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // Find ranges to skip (code blocks, frontmatter)
        var skipRanges: [NSRange] = []

        Self.frontmatterRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let range = match?.range { skipRanges.append(range) }
        }
        Self.codeBlockRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            if let range = match?.range { skipRanges.append(range) }
        }

        // Find headings, skipping those inside code blocks/frontmatter
        var items: [HeadingItem] = []
        Self.atxHeadingRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let matchRange = match.range

            // Skip if inside a code block or frontmatter
            for skip in skipRanges {
                if skip.location <= matchRange.location &&
                    NSMaxRange(skip) >= NSMaxRange(matchRange) {
                    return
                }
            }

            let hashRange = match.range(at: 1)
            let titleRange = match.range(at: 2)
            let level = hashRange.length
            let rawTitle = nsText.substring(with: titleRange)
            let title = Self.stripInlineMarkdown(rawTitle)
            let previewAnchor = Self.previewAnchor(for: matchRange, in: nsText)

            items.append(HeadingItem(level: level, title: title, range: matchRange, previewAnchor: previewAnchor))
        }

        Self.setextHeadingRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            let matchRange = match.range

            for skip in skipRanges {
                if skip.location <= matchRange.location &&
                    NSMaxRange(skip) >= NSMaxRange(matchRange) {
                    return
                }
            }

            let titleRange = match.range(at: 1)
            let markerRange = match.range(at: 2)
            let rawTitle = nsText.substring(with: titleRange)
            let title = Self.stripInlineMarkdown(rawTitle)
            let marker = nsText.substring(with: markerRange)
            let level = marker.first == "=" ? 1 : 2
            let previewAnchor = Self.previewAnchor(for: matchRange, in: nsText)

            items.append(HeadingItem(level: level, title: title, range: matchRange, previewAnchor: previewAnchor))
        }

        items.sort { lhs, rhs in
            lhs.range.location < rhs.range.location
        }

        DispatchQueue.main.async {
            self.headings = items
        }
    }

    /// Strip bold, italic, code, strikethrough, and link markdown from heading text
    private static func stripInlineMarkdown(_ text: String) -> String {
        var result = text
        // Links [text](url) → text
        result = result.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\([^)]+\\)",
            with: "$1",
            options: .regularExpression
        )
        // Images ![alt](url) → alt
        result = result.replacingOccurrences(
            of: "!\\[([^\\]]*)\\]\\([^)]+\\)",
            with: "$1",
            options: .regularExpression
        )
        // Bold **text** or __text__
        result = result.replacingOccurrences(
            of: "(\\*\\*|__)(.+?)\\1",
            with: "$2",
            options: .regularExpression
        )
        // Italic *text* or _text_ (simplified)
        result = result.replacingOccurrences(
            of: "(?<![\\w*])[*_](.+?)[*_](?![\\w*])",
            with: "$1",
            options: .regularExpression
        )
        // Strikethrough ~~text~~
        result = result.replacingOccurrences(
            of: "~~(.+?)~~",
            with: "$1",
            options: .regularExpression
        )
        // Inline code `text`
        result = result.replacingOccurrences(
            of: "`([^`]+)`",
            with: "$1",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func previewAnchor(for range: NSRange, in text: NSString) -> PreviewSourceAnchor {
        let start = lineAndColumn(for: range.location, in: text)
        let endOffset = max(range.location, NSMaxRange(range) - 1)
        let end = lineAndColumn(for: endOffset, in: text)
        return PreviewSourceAnchor(
            startLine: start.line,
            startColumn: start.column,
            endLine: end.line,
            endColumn: end.column,
            progress: 0
        )
    }

    private static func lineAndColumn(for offset: Int, in text: NSString) -> (line: Int, column: Int) {
        let clampedOffset = min(max(0, offset), text.length)
        var line = 1
        var lineStart = 0

        while lineStart < clampedOffset {
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            let nextLineStart = NSMaxRange(lineRange)
            if nextLineStart > clampedOffset {
                break
            }
            line += 1
            lineStart = nextLineStart
        }

        return (line, max(1, clampedOffset - lineStart + 1))
    }
}
