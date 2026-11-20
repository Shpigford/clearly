import Foundation

public struct NoteTemplate: Equatable, Identifiable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String

    public init(url: URL, name: String) {
        self.url = url
        self.name = name
    }
}

public struct NoteTemplateRender: Equatable, Sendable {
    public let prefix: String
    public let combined: String

    public init(prefix: String, combined: String) {
        self.prefix = prefix
        self.combined = combined
    }
}

public enum NoteTemplateEngine {
    public static let folderName = "Templates"

    public static func list(in vaultRoot: URL, fileManager: FileManager = .default) -> [NoteTemplate] {
        let folder = vaultRoot.appendingPathComponent(folderName, isDirectory: true)
        guard let items = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            return []
        }

        var templates: [NoteTemplate] = []
        for url in items {
            let filename = url.lastPathComponent
            guard filename.lowercased().hasSuffix(".md"), !filename.hasPrefix(".") else { continue }
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isFile == true else { continue }
            templates.append(NoteTemplate(url: url, name: url.deletingPathExtension().lastPathComponent))
        }
        templates.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return templates
    }

    public static func render(
        template: String,
        title: String,
        now: Date,
        existingText: String
    ) -> NoteTemplateRender {
        var text = stripQueryFences(from: template)
        text = stripEmptyCallouts(from: text)
        text = collapseExtraNewlines(text)
        text = expandPlaceholders(in: text, title: title, now: now)

        if existingText.isEmpty {
            return NoteTemplateRender(prefix: text, combined: text)
        }
        let prefix = text.trimmingCharacters(in: .newlines) + "\n\n"
        return NoteTemplateRender(prefix: prefix, combined: prefix + existingText)
    }

    // MARK: - Placeholders

    private static func expandPlaceholders(in text: String, title: String, now: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = .current
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = .current
        timeFormatter.dateFormat = "HH:mm"

        return text
            .replacingOccurrences(of: "{{date}}", with: dateFormatter.string(from: now))
            .replacingOccurrences(of: "{{time}}", with: timeFormatter.string(from: now))
            .replacingOccurrences(of: "{{title}}", with: title)
    }

    // MARK: - Dataview / JS fences

    private static func stripQueryFences(from source: String) -> String {
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var kept: [String] = []
        var index = 0
        while index < lines.count {
            if let language = fenceLanguage(lines[index]), isQueryLanguage(language) {
                index += 1
                while index < lines.count {
                    if let closer = fenceLanguage(lines[index]) {
                        index += 1
                        if closer.isEmpty || isQueryLanguage(closer) {
                            break
                        }
                        continue
                    }
                    index += 1
                }
                continue
            }
            kept.append(lines[index])
            index += 1
        }
        return kept.joined(separator: "\n")
    }

    /// Language token of a markdown fence, ignoring leading `>` quote markers.
    /// Empty string means a closing fence (` ``` `).
    private static func fenceLanguage(_ line: String) -> String? {
        var rest = line[...]
        while rest.first == ">" {
            rest = rest.dropFirst()
            if rest.first == " " { rest = rest.dropFirst() }
        }
        guard rest.hasPrefix("```") else { return nil }
        return rest.dropFirst(3)
            .trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init) ?? ""
    }

    private static func isQueryLanguage(_ language: String) -> Bool {
        let lowered = language.lowercased()
        return lowered == "dataview" || lowered == "dataviewjs"
    }

    // MARK: - Empty callouts left after fence stripping

    private static func stripEmptyCallouts(from source: String) -> String {
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var kept: [String] = []
        var index = 0
        while index < lines.count {
            if isCalloutHeader(lines[index]) {
                var cursor = index + 1
                var hasBody = false
                while cursor < lines.count, isQuotedLine(lines[cursor]) {
                    if !isBlankQuotedLine(lines[cursor]) {
                        hasBody = true
                        break
                    }
                    cursor += 1
                }
                if hasBody {
                    kept.append(lines[index])
                    index += 1
                } else {
                    index = cursor
                }
                continue
            }
            kept.append(lines[index])
            index += 1
        }
        return kept.joined(separator: "\n")
    }

    private static func isCalloutHeader(_ line: String) -> Bool {
        var rest = line[...]
        guard rest.first == ">" else { return false }
        rest = rest.dropFirst()
        if rest.first == " " { rest = rest.dropFirst() }
        return rest.hasPrefix("[!")
    }

    private static func isQuotedLine(_ line: String) -> Bool {
        line.hasPrefix(">")
    }

    private static func isBlankQuotedLine(_ line: String) -> Bool {
        var rest = line[...]
        guard rest.first == ">" else { return false }
        rest = rest.dropFirst()
        if rest.first == " " { rest = rest.dropFirst() }
        return rest.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func collapseExtraNewlines(_ text: String) -> String {
        let collapsed = text.replacingOccurrences(
            of: "\n{3,}",
            with: "\n\n",
            options: .regularExpression
        )
        return collapsed
    }
}
