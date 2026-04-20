import Foundation

public enum FrontmatterSupport {
    public struct Field {
        public let key: String
        public let value: String

        public init(key: String, value: String) {
            self.key = key
            self.value = value
        }
    }

    public struct Block {
        public let fields: [Field]
        public let rawText: String
        public let body: String
        public let lineCount: Int

        public init(fields: [Field], rawText: String, body: String, lineCount: Int) {
            self.fields = fields
            self.rawText = rawText
            self.body = body
            self.lineCount = lineCount
        }
    }

    public static func extract(from markdown: String) -> Block? {
        guard markdown.hasPrefix("---\n") || markdown.hasPrefix("---\r\n") else {
            return nil
        }

        let lines = markdown.components(separatedBy: "\n")
        var closingIndex: Int?

        for index in 1..<lines.count {
            let trimmed = normalizedLine(lines[index]).trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                closingIndex = index
                break
            }
        }

        guard let closeIdx = closingIndex else {
            return nil
        }

        let contentLines = Array(lines[1..<closeIdx]).map(normalizedLine)
        guard isLikelyFrontmatter(contentLines) else {
            return nil
        }

        let bodyStart = closeIdx + 1
        let body = bodyStart < lines.count ? lines[bodyStart...].joined(separator: "\n") : ""

        return Block(
            fields: parseFields(from: contentLines),
            rawText: contentLines.joined(separator: "\n"),
            body: body,
            lineCount: bodyStart
        )
    }

    private static func normalizedLine(_ line: String) -> String {
        line.hasSuffix("\r") ? String(line.dropLast()) : line
    }

    private static func isLikelyFrontmatter(_ lines: [String]) -> Bool {
        var sawField = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            if line.first?.isWhitespace == true || trimmed.hasPrefix("- ") {
                guard sawField else { return false }
                continue
            }

            guard fieldParts(in: line) != nil else {
                return false
            }

            sawField = true
        }

        return true
    }

    private static func parseFields(from lines: [String]) -> [Field] {
        var fields: [Field] = []
        var currentKey: String?
        var currentValueLines: [String] = []

        func flushField() {
            guard let key = currentKey else { return }
            let value = currentValueLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            fields.append(Field(key: key, value: value))
            currentKey = nil
            currentValueLines.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if currentKey != nil, !currentValueLines.isEmpty {
                    currentValueLines.append("")
                }
                continue
            }

            if trimmed.hasPrefix("#") {
                continue
            }

            if line.first?.isWhitespace == true || trimmed.hasPrefix("- ") {
                guard currentKey != nil else { continue }
                currentValueLines.append(trimmed)
                continue
            }

            if let (key, value) = fieldParts(in: line) {
                flushField()
                currentKey = key
                if !value.isEmpty {
                    currentValueLines = [value]
                }
            }
        }

        flushField()
        return fields
    }

    private static func fieldParts(in line: String) -> (String, String)? {
        guard let colonRange = line.range(of: ":") else {
            return nil
        }

        let key = String(line[line.startIndex..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }

        let value = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        return (key, value)
    }
}
