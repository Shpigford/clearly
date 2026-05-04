import Foundation

public enum MarkdownStats {
    public struct Counts: Equatable {
        public let totalWords: Int
        public let totalChars: Int
        public let totalReadingSeconds: Int
        public let selectionWords: Int
        public let selectionChars: Int
        public let hasSelection: Bool

        public static let empty = Counts(
            totalWords: 0, totalChars: 0, totalReadingSeconds: 0,
            selectionWords: 0, selectionChars: 0, hasSelection: false
        )

        public init(
            totalWords: Int, totalChars: Int, totalReadingSeconds: Int,
            selectionWords: Int, selectionChars: Int, hasSelection: Bool
        ) {
            self.totalWords = totalWords
            self.totalChars = totalChars
            self.totalReadingSeconds = totalReadingSeconds
            self.selectionWords = selectionWords
            self.selectionChars = selectionChars
            self.hasSelection = hasSelection
        }
    }

    public static let defaultWordsPerMinute = 265

    public static func compute(
        text: String,
        selectedRange: NSRange,
        wordsPerMinute: Int = defaultWordsPerMinute
    ) -> Counts {
        let strippedTotal = strip(text)
        let totalWords = countWords(strippedTotal)
        let totalChars = strippedTotal.count
        let wpm = max(wordsPerMinute, 1)
        let totalReadingSeconds = Int(
            (Double(totalWords) / Double(wpm) * 60.0).rounded(.up)
        )

        let nsText = text as NSString
        let hasSelection = selectedRange.length > 0
            && selectedRange.location >= 0
            && selectedRange.location + selectedRange.length <= nsText.length

        let selectionWords: Int
        let selectionChars: Int
        if hasSelection {
            let selectedSubstring = nsText.substring(with: selectedRange)
            let strippedSelection = strip(selectedSubstring)
            selectionWords = countWords(strippedSelection)
            selectionChars = strippedSelection.count
        } else {
            selectionWords = 0
            selectionChars = 0
        }

        return Counts(
            totalWords: totalWords,
            totalChars: totalChars,
            totalReadingSeconds: totalReadingSeconds,
            selectionWords: selectionWords,
            selectionChars: selectionChars,
            hasSelection: hasSelection
        )
    }

    // MARK: - Word counting

    private static func countWords(_ text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byWords, .localized]
        ) { substring, _, _, _ in
            if let s = substring, !s.isEmpty { count += 1 }
        }
        return count
    }

    // MARK: - Markdown stripping

    /// Returns a plain-text approximation of the input markdown suitable for
    /// counting words and characters. Drops syntactic markers (headings,
    /// emphasis, list bullets, code fences, etc.) and link/image URL targets;
    /// preserves the human-readable content (link labels, code body, etc.).
    static func strip(_ input: String) -> String {
        var s = input

        // 1. Drop YAML frontmatter at the very top of the document.
        s = stripFrontmatter(s)

        // 2. Replace fenced code blocks with their inner text (keep code as
        //    content; matches iA Writer / Bear behavior).
        s = stripFencedCodeBlocks(s)

        // 3. Replace inline code spans with their inner text.
        s = replace(s, pattern: "`([^`\\n]*)`", template: "$1")

        // 4. Strip raw HTML tags.
        s = replace(s, pattern: "<[^>]+>", template: "")

        // 5. Wiki-links: [[Page]], [[Page#heading]], [[Page|alias]],
        //    [[Page#heading|alias]] → alias (or page+heading text).
        s = stripWikiLinks(s)

        // 6. Image syntax: ![alt](url) → drop entirely (alt text and URL
        //    are not user-visible prose).
        s = replace(s, pattern: "!\\[[^\\]]*\\]\\([^)]*\\)", template: "")
        s = replace(s, pattern: "!\\[[^\\]]*\\]\\[[^\\]]*\\]", template: "")

        // 7. Link syntax: [label](url) → label.
        s = replace(s, pattern: "\\[([^\\]]+)\\]\\([^)]*\\)", template: "$1")
        //    Reference links: [label][id] → label.
        s = replace(s, pattern: "\\[([^\\]]+)\\]\\[[^\\]]*\\]", template: "$1")
        //    Reference link definitions: [id]: url "title" — drop entire line.
        s = replace(
            s,
            pattern: "(?m)^\\s*\\[[^\\]]+\\]:\\s*\\S.*$",
            template: ""
        )

        // 8. Footnote references and definitions.
        s = replace(s, pattern: "\\[\\^[^\\]]+\\]", template: "")

        // 9. ATX heading markers.
        s = replace(s, pattern: "(?m)^\\s{0,3}#{1,6}\\s+", template: "")

        // 10. Setext heading underlines (lines of all = or -).
        s = replace(s, pattern: "(?m)^[=\\-]{3,}\\s*$", template: "")
        // Horizontal rules of *.
        s = replace(s, pattern: "(?m)^\\s*\\*{3,}\\s*$", template: "")

        // 11. Blockquote markers.
        s = replace(s, pattern: "(?m)^[ \\t]*>+\\s?", template: "")

        // 12. Task list markers, then list bullets / ordered list numbers.
        s = replace(
            s,
            pattern: "(?m)^[ \\t]*(?:[-*+]|\\d+\\.)\\s+\\[[ xX]\\]\\s*",
            template: ""
        )
        s = replace(
            s,
            pattern: "(?m)^[ \\t]*(?:[-*+]|\\d+\\.)\\s+",
            template: ""
        )

        // 13. Emphasis / strong / strike / highlight. Strip in pair-aware
        //     order so triple markers degrade cleanly.
        s = replace(s, pattern: "\\*\\*\\*([^*\\n]+?)\\*\\*\\*", template: "$1")
        s = replace(s, pattern: "\\*\\*([^*\\n]+?)\\*\\*", template: "$1")
        s = replace(s, pattern: "\\*([^*\\n]+?)\\*", template: "$1")
        s = replace(s, pattern: "~~([^~\\n]+?)~~", template: "$1")
        s = replace(s, pattern: "==([^=\\n]+?)==", template: "$1")

        return s
    }

    private static func stripFrontmatter(_ s: String) -> String {
        // YAML frontmatter must start at the very first character.
        guard s.hasPrefix("---\n") || s.hasPrefix("---\r\n") else { return s }
        let pattern = "\\A---\\r?\\n[\\s\\S]*?\\r?\\n---\\r?\\n?"
        return replace(s, pattern: pattern, template: "")
    }

    private static func stripFencedCodeBlocks(_ s: String) -> String {
        // (?ms) so . matches newlines and ^$ match line boundaries.
        // Matches ``` or ~~~ fences with optional info string on the same line.
        let pattern = "(?ms)^[ \\t]{0,3}(```+|~~~+)[^\\n]*\\n([\\s\\S]*?)\\n[ \\t]{0,3}\\1[ \\t]*$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let nsString = s as NSString
        let range = NSRange(location: 0, length: nsString.length)

        var output = ""
        var cursor = 0
        regex.enumerateMatches(in: s, options: [], range: range) { match, _, _ in
            guard let match else { return }
            let pre = NSRange(location: cursor, length: match.range.location - cursor)
            output.append(nsString.substring(with: pre))
            if match.numberOfRanges >= 3 {
                let inner = match.range(at: 2)
                if inner.location != NSNotFound {
                    output.append(nsString.substring(with: inner))
                }
            }
            cursor = match.range.location + match.range.length
        }
        if cursor < nsString.length {
            output.append(nsString.substring(with: NSRange(location: cursor, length: nsString.length - cursor)))
        }
        return output
    }

    private static func stripWikiLinks(_ s: String) -> String {
        let pattern = "\\[\\[([^\\]\\|#\\n]+)(?:#([^\\]\\|\\n]+))?(?:\\|([^\\]\\n]+))?\\]\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let nsString = s as NSString
        let range = NSRange(location: 0, length: nsString.length)

        var output = ""
        var cursor = 0
        regex.enumerateMatches(in: s, options: [], range: range) { match, _, _ in
            guard let match else { return }
            let pre = NSRange(location: cursor, length: match.range.location - cursor)
            output.append(nsString.substring(with: pre))

            let aliasRange = match.range(at: 3)
            let headingRange = match.range(at: 2)
            let pageRange = match.range(at: 1)

            if aliasRange.location != NSNotFound {
                output.append(nsString.substring(with: aliasRange))
            } else if headingRange.location != NSNotFound {
                let page = pageRange.location != NSNotFound
                    ? nsString.substring(with: pageRange) : ""
                let heading = nsString.substring(with: headingRange)
                output.append(page.isEmpty ? heading : "\(page) \(heading)")
            } else if pageRange.location != NSNotFound {
                output.append(nsString.substring(with: pageRange))
            }

            cursor = match.range.location + match.range.length
        }
        if cursor < nsString.length {
            output.append(nsString.substring(with: NSRange(location: cursor, length: nsString.length - cursor)))
        }
        return output
    }

    private static func replace(_ s: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(location: 0, length: (s as NSString).length)
        return regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: template)
    }
}
