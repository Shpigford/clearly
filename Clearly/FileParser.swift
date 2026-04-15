import Foundation

// MARK: - Data Types

struct ParsedLink: Equatable {
    let target: String
    let heading: String?
    let alias: String?
    let lineNumber: Int
}

struct ParsedTag: Equatable {
    enum Source: String {
        case inline
        case frontmatter
    }
    let name: String      // normalized: lowercase, no #
    let lineNumber: Int
    let source: Source
}

struct ParsedHeading: Equatable {
    let text: String
    let level: Int        // 1-6
    let lineNumber: Int
}

struct ParseResult {
    let links: [ParsedLink]
    let tags: [ParsedTag]
    let headings: [ParsedHeading]
}

// MARK: - Parser

enum FileParser {

    // MARK: Regexes

    private static let codeBlockRegex = try! NSRegularExpression(
        pattern: "^((?:`{3,}|~{3,}))[^\n]*\\n([\\s\\S]*?)^\\1[ \\t]*$",
        options: [.anchorsMatchLines]
    )

    private static let frontmatterRegex = try! NSRegularExpression(
        pattern: "\\A---[ \\t]*\\n([\\s\\S]*?)\\n---[ \\t]*(?:\\n|\\z)",
        options: []
    )

    private static let wikiLinkRegex = try! NSRegularExpression(
        pattern: #"\[\[([^\]\|#\^]+?)(?:#([^\]\|]+?))?(?:\|([^\]]+?))?\]\]"#,
        options: []
    )

    private static let tagRegex = try! NSRegularExpression(
        pattern: #"(?:^|(?<=\s))#([\p{L}\p{N}_\-/]*[\p{L}_\-/][\p{L}\p{N}_\-/]*)"#,
        options: [.anchorsMatchLines]
    )

    private static let headingRegex = try! NSRegularExpression(
        pattern: "^(#{1,6})\\s+(.+)$",
        options: [.anchorsMatchLines]
    )

    // MARK: Public API

    static func parse(content: String) -> ParseResult {
        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)

        // Build skip ranges (code blocks + frontmatter)
        var skipRanges: [NSRange] = []

        frontmatterRegex.enumerateMatches(in: content, range: fullRange) { match, _, _ in
            if let range = match?.range { skipRanges.append(range) }
        }
        codeBlockRegex.enumerateMatches(in: content, range: fullRange) { match, _, _ in
            if let range = match?.range { skipRanges.append(range) }
        }

        let links = extractLinks(from: content, nsContent: nsContent, fullRange: fullRange, skipRanges: skipRanges)
        let inlineTags = extractTags(from: content, nsContent: nsContent, fullRange: fullRange, skipRanges: skipRanges)
        let frontmatterTags = extractFrontmatterTags(from: content)
        let headings = extractHeadings(from: content, nsContent: nsContent, fullRange: fullRange, skipRanges: skipRanges)

        return ParseResult(
            links: links,
            tags: inlineTags + frontmatterTags,
            headings: headings
        )
    }

    // MARK: Extraction

    private static func extractLinks(from text: String, nsContent: NSString, fullRange: NSRange, skipRanges: [NSRange]) -> [ParsedLink] {
        var links: [ParsedLink] = []

        wikiLinkRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            guard !isInsideSkipRange(match.range, skipRanges: skipRanges) else { return }

            let target = nsContent.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespaces)

            var heading: String?
            let headingRange = match.range(at: 2)
            if headingRange.location != NSNotFound {
                heading = nsContent.substring(with: headingRange)
                    .trimmingCharacters(in: .whitespaces)
            }

            var alias: String?
            let aliasRange = match.range(at: 3)
            if aliasRange.location != NSNotFound {
                alias = nsContent.substring(with: aliasRange)
                    .trimmingCharacters(in: .whitespaces)
            }

            let line = lineNumber(at: match.range.location, in: nsContent)
            links.append(ParsedLink(target: target, heading: heading, alias: alias, lineNumber: line))
        }

        return links
    }

    private static func extractTags(from text: String, nsContent: NSString, fullRange: NSRange, skipRanges: [NSRange]) -> [ParsedTag] {
        var tags: [ParsedTag] = []

        tagRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            guard !isInsideSkipRange(match.range, skipRanges: skipRanges) else { return }

            let name = nsContent.substring(with: match.range(at: 1)).lowercased()
            let line = lineNumber(at: match.range.location, in: nsContent)
            tags.append(ParsedTag(name: name, lineNumber: line, source: .inline))
        }

        return tags
    }

    private static func extractFrontmatterTags(from content: String) -> [ParsedTag] {
        guard let block = FrontmatterSupport.extract(from: content) else { return [] }

        guard let tagsField = block.fields.first(where: { $0.key.lowercased() == "tags" }) else { return [] }

        let value = tagsField.value
        var tagNames: [String] = []

        // Handle YAML list: [tag1, tag2] or each line "- tag"
        if value.hasPrefix("[") && value.hasSuffix("]") {
            // Inline array: [tag1, tag2, tag3]
            let inner = String(value.dropFirst().dropLast())
            tagNames = inner.components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        } else {
            // Could be a single value on the same line or multi-line list
            let lines = value.components(separatedBy: "\n")
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- ") {
                    let tag = String(trimmed.dropFirst(2))
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if !tag.isEmpty { tagNames.append(tag) }
                } else if trimmed.contains(",") {
                    // Bare comma-separated: tags: foo, bar, baz
                    tagNames.append(contentsOf: trimmed.components(separatedBy: ",").map {
                        $0.trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    })
                } else if !trimmed.isEmpty {
                    // Single value on same line as key
                    tagNames.append(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")))
                }
            }
        }

        return tagNames.compactMap { name in
            let normalized = name.lowercased().trimmingCharacters(in: .whitespaces)
            guard !normalized.isEmpty else { return nil }
            // Frontmatter tags are on line 1 (inside the frontmatter block)
            return ParsedTag(name: normalized, lineNumber: 1, source: .frontmatter)
        }
    }

    private static func extractHeadings(from text: String, nsContent: NSString, fullRange: NSRange, skipRanges: [NSRange]) -> [ParsedHeading] {
        var headings: [ParsedHeading] = []

        headingRegex.enumerateMatches(in: text, range: fullRange) { match, _, _ in
            guard let match else { return }
            guard !isInsideSkipRange(match.range, skipRanges: skipRanges) else { return }

            let level = match.range(at: 1).length
            let rawTitle = nsContent.substring(with: match.range(at: 2))
            let title = stripInlineMarkdown(rawTitle)
            let line = lineNumber(at: match.range.location, in: nsContent)

            headings.append(ParsedHeading(text: title, level: level, lineNumber: line))
        }

        return headings
    }

    // MARK: Helpers

    private static func isInsideSkipRange(_ range: NSRange, skipRanges: [NSRange]) -> Bool {
        for skip in skipRanges {
            if skip.location <= range.location && NSMaxRange(skip) >= NSMaxRange(range) {
                return true
            }
        }
        return false
    }

    /// Returns 1-based line number for a character offset.
    private static func lineNumber(at offset: Int, in text: NSString) -> Int {
        let clamped = min(max(0, offset), text.length)
        var line = 1
        var pos = 0
        while pos < clamped {
            let lineRange = text.lineRange(for: NSRange(location: pos, length: 0))
            let nextPos = NSMaxRange(lineRange)
            if nextPos > clamped { break }
            line += 1
            pos = nextPos
        }
        return line
    }

    /// Strip bold, italic, code, strikethrough, link markdown from heading text.
    private static func stripInlineMarkdown(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "!\\[([^\\]]*)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "(\\*\\*|__)(.+?)\\1", with: "$2", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?<![\\w*])[*_](.+?)[*_](?![\\w*])", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "~~(.+?)~~", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "`([^`]+)`", with: "$1", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespaces)
    }
}
