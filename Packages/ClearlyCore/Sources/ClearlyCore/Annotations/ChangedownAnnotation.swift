import Foundation

public struct ChangedownAnnotationEntry: Equatable, Sendable {
    public var author: String?
    public var date: String?
    public var text: String

    public init(author: String? = nil, date: String? = nil, text: String) {
        self.author = author
        self.date = date
        self.text = text
    }
}

public struct ChangedownAnnotationFootnote: Equatable, Sendable {
    public var id: String
    public var author: String?
    public var date: String?
    public var kind: String?
    public var status: String?
    public var entries: [ChangedownAnnotationEntry]
    public var lineRange: ClosedRange<Int>

    public init(
        id: String,
        author: String? = nil,
        date: String? = nil,
        kind: String? = nil,
        status: String? = nil,
        entries: [ChangedownAnnotationEntry] = [],
        lineRange: ClosedRange<Int>
    ) {
        self.id = id
        self.author = author
        self.date = date
        self.kind = kind
        self.status = status
        self.entries = entries
        self.lineRange = lineRange
    }

    public var summary: String? {
        entries.first?.text
    }
}

public struct ChangedownAnnotation: Equatable, Sendable {
    public var id: String
    public var highlightedText: String
    public var inlineComment: String?
    public var footnote: ChangedownAnnotationFootnote?

    public init(
        id: String,
        highlightedText: String,
        inlineComment: String? = nil,
        footnote: ChangedownAnnotationFootnote? = nil
    ) {
        self.id = id
        self.highlightedText = highlightedText
        self.inlineComment = inlineComment
        self.footnote = footnote
    }
}

public struct ChangedownAnnotationProjectionResult: Equatable, Sendable {
    public var markdown: String
    public var annotations: [String: ChangedownAnnotation]

    public init(markdown: String, annotations: [String: ChangedownAnnotation]) {
        self.markdown = markdown
        self.annotations = annotations
    }
}

