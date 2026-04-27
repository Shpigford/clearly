import Foundation

public enum ChangedownAnnotationProjection {
    private static let highlightWithCommentRegex = try! NSRegularExpression(
        pattern: #"\{==([\s\S]+?)==\}\{>>\s*([\s\S]+?)\s*<<\}\[\^(cn-[A-Za-z0-9.-]+)\]"#,
        options: []
    )

    private static let highlightWithFootnoteRegex = try! NSRegularExpression(
        pattern: #"\{==([\s\S]+?)==\}\[\^(cn-[A-Za-z0-9.-]+)\]"#,
        options: []
    )

    public static func project(_ markdown: String) -> ChangedownAnnotationProjectionResult {
        let footnotes = ChangedownAnnotationParser.parseFootnotes(in: markdown)
        var annotations: [String: ChangedownAnnotation] = [:]

        var projected = replaceMatches(in: markdown, regex: highlightWithCommentRegex) { match, source in
            let highlighted = substring(in: source, match.range(at: 1))
            let inlineComment = substring(in: source, match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            let id = substring(in: source, match.range(at: 3))
            let footnote = footnotes[id]
            annotations[id] = ChangedownAnnotation(
                id: id,
                highlightedText: highlighted,
                inlineComment: inlineComment,
                footnote: footnote
            )
            return annotationHTML(
                id: id,
                text: highlighted,
                comment: footnote?.summary ?? (inlineComment.isEmpty ? nil : inlineComment),
                footnote: footnote
            )
        }

        projected = replaceMatches(in: projected, regex: highlightWithFootnoteRegex) { match, source in
            let highlighted = substring(in: source, match.range(at: 1))
            let id = substring(in: source, match.range(at: 2))

            guard annotations[id] == nil else {
                return substring(in: source, match.range)
            }

            let footnote = footnotes[id]
            annotations[id] = ChangedownAnnotation(
                id: id,
                highlightedText: highlighted,
                inlineComment: nil,
                footnote: footnote
            )
            return annotationHTML(
                id: id,
                text: highlighted,
                comment: footnote?.summary,
                footnote: footnote
            )
        }

        if !annotations.isEmpty {
            projected = removeRenderedFootnotes(from: projected, renderedIds: Set(annotations.keys))
        }

        return ChangedownAnnotationProjectionResult(markdown: projected, annotations: annotations)
    }

    private static func replaceMatches(
        in text: String,
        regex: NSRegularExpression,
        transform: (NSTextCheckingResult, String) -> String
    ) -> String {
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: transform(match, text))
        }
        return result
    }

    private static func removeRenderedFootnotes(from markdown: String, renderedIds: Set<String>) -> String {
        let lines = markdown.components(separatedBy: "\n")
        let footnotes = ChangedownAnnotationParser.parseFootnotes(in: markdown)
        let blockedLineIndices = Set(
            footnotes.values
                .filter { renderedIds.contains($0.id) }
                .flatMap { Array($0.lineRange) }
        )

        guard !blockedLineIndices.isEmpty else { return markdown }

        var filteredLines: [String] = []
        filteredLines.reserveCapacity(lines.count)

        for (index, line) in lines.enumerated() where !blockedLineIndices.contains(index) {
            filteredLines.append(line)
        }

        while filteredLines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            filteredLines.removeLast()
        }

        return filteredLines.joined(separator: "\n")
    }

    private static func annotationHTML(
        id: String,
        text: String,
        comment: String?,
        footnote: ChangedownAnnotationFootnote?
    ) -> String {
        var attributes = [
            #"class="cd-annotation""#,
            #"data-change-id="\#(escapeAttribute(id))""#
        ]

        if let comment, !comment.isEmpty {
            attributes.append(#"data-comment="\#(escapeAttribute(comment))""#)
            attributes.append(#"title="\#(escapeAttribute(comment))""#)
        }
        if let author = footnote?.author, !author.isEmpty {
            attributes.append(#"data-author="\#(escapeAttribute(author))""#)
        }
        if let date = footnote?.date, !date.isEmpty {
            attributes.append(#"data-date="\#(escapeAttribute(date))""#)
        }
        if let status = footnote?.status, !status.isEmpty {
            attributes.append(#"data-status="\#(escapeAttribute(status))""#)
        }

        return #"<span \#(attributes.joined(separator: " "))>\#(escapeHTML(text))</span>"#
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttribute(_ text: String) -> String {
        escapeHTML(text)
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\n", with: "&#10;")
    }

    private static func substring(in string: String, _ range: NSRange) -> String {
        guard let swiftRange = Range(range, in: string) else { return "" }
        return String(string[swiftRange])
    }
}
