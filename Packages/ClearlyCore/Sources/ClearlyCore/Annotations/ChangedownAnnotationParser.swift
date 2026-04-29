import Foundation

public enum ChangedownAnnotationParser {
    private static let headerRegex = try! NSRegularExpression(
        pattern: #"^\[\^(cn-[A-Za-z0-9.-]+)\]:\s*(.*)$"#,
        options: []
    )

    private static let discussionRegex = try! NSRegularExpression(
        pattern: #"^\s*(@[^\s:]+)\s+(\d{4}-\d{2}-\d{2})(?:\s+\[[^\]]+\])?:\s*(.*)$"#,
        options: []
    )

    public static func parseFootnotes(in markdown: String) -> [String: ChangedownAnnotationFootnote] {
        let lines = markdown.components(separatedBy: "\n")
        var result: [String: ChangedownAnnotationFootnote] = [:]
        var lineIndex = 0

        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let fullRange = NSRange(location: 0, length: (line as NSString).length)

            guard let match = headerRegex.firstMatch(in: line, range: fullRange) else {
                lineIndex += 1
                continue
            }

            let id = substring(in: line, match.range(at: 1))
            let headerContent = substring(in: line, match.range(at: 2))
            let headerParts = headerContent
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }

            let author = headerParts.indices.contains(0) && !headerParts[0].isEmpty ? headerParts[0] : nil
            let date = headerParts.indices.contains(1) && !headerParts[1].isEmpty ? headerParts[1] : nil
            let kind = headerParts.indices.contains(2) && !headerParts[2].isEmpty ? headerParts[2] : nil
            let status = headerParts.indices.contains(3) && !headerParts[3].isEmpty ? headerParts[3] : nil

            var endLine = lineIndex
            var entries: [ChangedownAnnotationEntry] = []
            var scanIndex = lineIndex + 1

            while scanIndex < lines.count {
                let candidate = lines[scanIndex]
                let trimmed = candidate.trimmingCharacters(in: .whitespaces)

                if trimmed.isEmpty {
                    endLine = scanIndex
                    scanIndex += 1
                    continue
                }

                guard candidate.hasPrefix("    ") || candidate.hasPrefix("\t") else {
                    break
                }

                if let entry = parseDiscussionEntry(from: candidate) {
                    entries.append(entry)
                } else if let fallback = parseFallbackEntry(from: trimmed) {
                    entries.append(fallback)
                }

                endLine = scanIndex
                scanIndex += 1
            }

            result[id] = ChangedownAnnotationFootnote(
                id: id,
                author: author,
                date: date,
                kind: kind,
                status: status,
                entries: entries,
                lineRange: lineIndex...endLine
            )

            lineIndex = max(scanIndex, lineIndex + 1)
        }

        return result
    }

    private static func parseDiscussionEntry(from line: String) -> ChangedownAnnotationEntry? {
        let range = NSRange(location: 0, length: (line as NSString).length)
        guard let match = discussionRegex.firstMatch(in: line, range: range) else { return nil }
        let text = substring(in: line, match.range(at: 3)).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return ChangedownAnnotationEntry(
            author: substring(in: line, match.range(at: 1)),
            date: substring(in: line, match.range(at: 2)),
            text: text
        )
    }

    private static func parseFallbackEntry(from trimmed: String) -> ChangedownAnnotationEntry? {
        if let colonIndex = trimmed.firstIndex(of: ":") {
            let text = trimmed[trimmed.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : ChangedownAnnotationEntry(text: text)
        }
        return trimmed.isEmpty ? nil : ChangedownAnnotationEntry(text: trimmed)
    }

    private static func substring(in string: String, _ range: NSRange) -> String {
        guard let swiftRange = Range(range, in: string) else { return "" }
        return String(string[swiftRange])
    }
}

