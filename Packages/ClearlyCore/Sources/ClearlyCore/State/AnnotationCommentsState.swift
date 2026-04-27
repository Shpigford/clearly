import Foundation

public struct AnnotationCommentItem: Identifiable, Hashable {
    public let id: String
    public let highlightedText: String
    public let comment: String?
    public let author: String?
    public let date: String?
    public let status: String?
    public let sourceRange: NSRange
    public let previewAnchor: PreviewSourceAnchor

    public init(
        id: String,
        highlightedText: String,
        comment: String?,
        author: String?,
        date: String?,
        status: String?,
        sourceRange: NSRange,
        previewAnchor: PreviewSourceAnchor
    ) {
        self.id = id
        self.highlightedText = highlightedText
        self.comment = comment
        self.author = author
        self.date = date
        self.status = status
        self.sourceRange = sourceRange
        self.previewAnchor = previewAnchor
    }
}

public final class AnnotationCommentsState: ObservableObject {
    @Published public var isVisible: Bool {
        didSet { UserDefaults.standard.set(isVisible, forKey: Self.visibilityKey) }
    }
    @Published public private(set) var comments: [AnnotationCommentItem] = []

    private static let visibilityKey = "annotationCommentsVisible"
    private static let inlineAnnotationRegex = try! NSRegularExpression(
        pattern: #"\{==([^\n\r]*?)==\}(?:\{>>\s*([^\n\r]*?)\s*<<\})?\[\^(cn-[A-Za-z0-9.-]+)\]"#,
        options: []
    )

    public init() {
        self.isVisible = UserDefaults.standard.bool(forKey: Self.visibilityKey)
    }

    public func toggle() {
        isVisible.toggle()
    }

    public func parseComments(from markdown: String) {
        let nsMarkdown = markdown as NSString
        let fullRange = NSRange(location: 0, length: nsMarkdown.length)
        let footnotes = ChangedownAnnotationParser.parseFootnotes(in: markdown)

        let parsed = Self.inlineAnnotationRegex.matches(in: markdown, range: fullRange).map { match in
            let id = Self.substring(in: nsMarkdown, match.range(at: 3))
            let highlightedText = Self.normalizeDisplayText(Self.substring(in: nsMarkdown, match.range(at: 1)))
            let inlineComment = match.range(at: 2).location == NSNotFound
                ? nil
                : Self.normalizeOptionalText(Self.substring(in: nsMarkdown, match.range(at: 2)))
            let footnote = footnotes[id]
            let highlightRange = match.range(at: 1)
            return AnnotationCommentItem(
                id: id,
                highlightedText: highlightedText,
                comment: footnote?.summary ?? inlineComment,
                author: footnote?.author,
                date: footnote?.date,
                status: footnote?.status,
                sourceRange: highlightRange,
                previewAnchor: Self.previewAnchor(for: highlightRange, in: nsMarkdown)
            )
        }

        comments = parsed
    }

    private static func substring(in string: NSString, _ range: NSRange) -> String {
        guard range.location != NSNotFound else { return "" }
        return string.substring(with: range)
    }

    private static func normalizeDisplayText(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "Untitled selection" : normalized
    }

    private static func normalizeOptionalText(_ text: String) -> String? {
        let normalized = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
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
