import Foundation

public enum ChangedownAnnotationWriterError: Error, Equatable, LocalizedError {
    case invalidRange
    case emptySelection
    case emptyComment
    case multilineSelection
    case unsupportedSelection(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRange:
            return "The selected text is no longer available."
        case .emptySelection:
            return "Select text before adding an annotation."
        case .emptyComment:
            return "Enter a note before adding an annotation."
        case .multilineSelection:
            return "Annotations currently support selections within one paragraph or list item."
        case .unsupportedSelection(let reason):
            return reason
        }
    }
}

public enum ChangedownAnnotationWriter {
    private static let idRegex = try! NSRegularExpression(
        pattern: #"\[\^cn-(\d+)\]"#,
        options: []
    )
    private static let inlineAnnotationRegex = try! NSRegularExpression(
        pattern: #"\{==[^\n\r]*?==\}(?:\{>>[^\n\r]*?<<\})?\[\^cn-[A-Za-z0-9.-]+\]"#,
        options: []
    )

    public static func addAnnotation(
        to markdown: String,
        utf16Range: NSRange,
        comment: String,
        author: String,
        date: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws -> String {
        guard let range = Range(utf16Range, in: markdown) else {
            throw ChangedownAnnotationWriterError.invalidRange
        }

        return try addAnnotation(
            to: markdown,
            range: range,
            comment: comment,
            author: author,
            date: date,
            calendar: calendar
        )
    }

    public static func addAnnotation(
        to markdown: String,
        range: Range<String.Index>,
        comment: String,
        author: String,
        date: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) throws -> String {
        let selected = String(markdown[range])
        let normalizedComment = normalizeComment(comment)
        let normalizedAuthor = normalizeAuthor(author)

        try validate(markdown: markdown, range: range, selected: selected, comment: normalizedComment)

        let id = nextAnnotationID(in: markdown)
        var result = markdown
        result.replaceSubrange(range, with: "{==\(selected)==}[^\(id)]")

        let stamp = dateStamp(for: date, calendar: calendar)
        let footnote = """

        [^\(id)]: \(normalizedAuthor) | \(stamp) | comment | proposed
            \(normalizedAuthor) \(stamp): \(normalizedComment)
        """

        if result.hasSuffix("\n\n") {
            result += String(footnote.dropFirst(2))
        } else if result.hasSuffix("\n") {
            result += footnote.dropFirst()
        } else {
            result += footnote
        }

        return result
    }

    private static func validate(
        markdown: String,
        range: Range<String.Index>,
        selected: String,
        comment: String
    ) throws {
        guard !selected.isEmpty else {
            throw ChangedownAnnotationWriterError.emptySelection
        }
        guard !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChangedownAnnotationWriterError.emptySelection
        }
        guard !comment.isEmpty else {
            throw ChangedownAnnotationWriterError.emptyComment
        }
        guard !selected.contains("\n") && !selected.contains("\r") else {
            throw ChangedownAnnotationWriterError.multilineSelection
        }
        guard !containsAnnotationMarker(selected) else {
            throw ChangedownAnnotationWriterError.unsupportedSelection("Selections inside annotation markup are not supported yet.")
        }

        let lineRange = markdown.lineRange(for: range)
        let line = String(markdown[lineRange])
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.hasPrefix("[^") else {
            throw ChangedownAnnotationWriterError.unsupportedSelection("Selections inside footnote definitions are not supported.")
        }
        guard !trimmed.hasPrefix("|"), !isTableSeparator(trimmed) else {
            throw ChangedownAnnotationWriterError.unsupportedSelection("Selections inside tables are not supported yet.")
        }
        guard !overlapsExistingAnnotation(markdown: markdown, range: range) else {
            throw ChangedownAnnotationWriterError.unsupportedSelection("Selections inside existing annotations are not supported yet.")
        }
        guard !isInsideFencedCode(markdown: markdown, range: range) else {
            throw ChangedownAnnotationWriterError.unsupportedSelection("Selections inside code blocks are not supported.")
        }
    }

    private static func nextAnnotationID(in markdown: String) -> String {
        let nsMarkdown = markdown as NSString
        let matches = idRegex.matches(
            in: markdown,
            range: NSRange(location: 0, length: nsMarkdown.length)
        )
        let maxID = matches.compactMap { match -> Int? in
            Int(nsMarkdown.substring(with: match.range(at: 1)))
        }.max() ?? 0
        return "cn-\(maxID + 1)"
    }

    private static func isInsideFencedCode(markdown: String, range: Range<String.Index>) -> Bool {
        let selectedOffset = markdown.distance(from: markdown.startIndex, to: range.lowerBound)
        var offset = 0
        var insideFence = false

        for rawLine in markdown.components(separatedBy: "\n") {
            let lineLengthWithSeparator = rawLine.count + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                insideFence.toggle()
            }
            if offset <= selectedOffset && selectedOffset < offset + lineLengthWithSeparator {
                return insideFence
            }
            offset += lineLengthWithSeparator
        }

        return false
    }

    private static func overlapsExistingAnnotation(markdown: String, range: Range<String.Index>) -> Bool {
        let nsMarkdown = markdown as NSString
        let selectionRange = NSRange(range, in: markdown)
        let matches = inlineAnnotationRegex.matches(
            in: markdown,
            range: NSRange(location: 0, length: nsMarkdown.length)
        )

        return matches.contains { NSIntersectionRange($0.range, selectionRange).length > 0 }
    }

    private static func containsAnnotationMarker(_ text: String) -> Bool {
        text.contains("{==") ||
            text.contains("==}") ||
            text.contains("{>>") ||
            text.contains("<<}") ||
            text.contains("[^cn-")
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        line.range(
            of: #"^\|?(?:\s*:?-+:?\s*\|)+\s*:?-+:?\s*\|?$"#,
            options: .regularExpression
        ) != nil
    }

    private static func normalizeComment(_ comment: String) -> String {
        comment
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func normalizeAuthor(_ author: String) -> String {
        let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "@me" }
        return trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
    }

    private static func dateStamp(for date: Date, calendar: Calendar) -> String {
        var calendar = calendar
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }
}
