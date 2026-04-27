import Foundation

/// Parsed entry from a vault's `log.md`. Matches the format
/// `WikiLogWriter.formatEntry` produces: a `## [YYYY-MM-DD HH:MM] kind — title`
/// heading followed by rationale paragraphs and a `- verb \`path\`` list. We
/// only surface the fields the UI needs — the raw body is kept around so a
/// future "view full entry" action can show it verbatim.
public struct WikiLogEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: String  // raw "YYYY-MM-DD HH:MM" — display only
    public let kind: String       // "ingest" / "query" / "lint" / ...
    public let title: String
    public let rationale: String
    public let changes: [ChangeRef]
    public let rawBody: String    // everything between this heading and the next

    public struct ChangeRef: Equatable, Sendable {
        public let verb: String   // "create" / "modify" / "delete"
        public let path: String
    }

    public init(
        id: UUID = UUID(),
        timestamp: String,
        kind: String,
        title: String,
        rationale: String,
        changes: [ChangeRef],
        rawBody: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.title = title
        self.rationale = rationale
        self.changes = changes
        self.rawBody = rawBody
    }
}

public enum WikiLogParser {

    /// Parse the raw contents of a vault's `log.md`. Entries are returned
    /// newest-first so the sidebar can render them without re-sorting.
    /// Unrecognised content outside of entry headings is silently ignored —
    /// users are expected to edit log.md freely.
    public static func parse(_ markdown: String) -> [WikiLogEntry] {
        let lines = markdown.components(separatedBy: "\n")
        var entries: [WikiLogEntry] = []

        // Scan for headings that match `## [YYYY-MM-DD HH:MM] kind — title`.
        // We accept the en/em dash or a plain hyphen as the separator.
        var headingIndices: [(line: Int, header: Header)] = []
        var isInFence = false
        for (idx, raw) in lines.enumerated() {
            if raw.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                isInFence.toggle()
                continue
            }
            if isInFence { continue }
            if let header = parseHeader(raw) {
                headingIndices.append((idx, header))
            }
        }

        for (position, entry) in headingIndices.enumerated() {
            let bodyStart = entry.line + 1
            let bodyEnd = position + 1 < headingIndices.count
                ? headingIndices[position + 1].line
                : lines.count
            let bodyLines = Array(lines[bodyStart..<bodyEnd])
            let (rationale, changes) = splitBody(bodyLines)
            let body = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            entries.append(WikiLogEntry(
                timestamp: entry.header.timestamp,
                kind: entry.header.kind,
                title: entry.header.title,
                rationale: rationale,
                changes: changes,
                rawBody: body
            ))
        }

        return entries.reversed()
    }

    // MARK: - Private

    private struct Header {
        let timestamp: String
        let kind: String
        let title: String
    }

    private static func parseHeader(_ line: String) -> Header? {
        // Minimal grammar: `## [<timestamp>] <kind> <sep> <title>`.
        guard line.hasPrefix("## [") else { return nil }
        guard let closeBracket = line.range(of: "] ") else { return nil }
        let timestamp = String(line[line.index(line.startIndex, offsetBy: 4)..<closeBracket.lowerBound])
        let rest = String(line[closeBracket.upperBound...])

        // Split on the first en-dash / em-dash / plain hyphen.
        let separators = [" — ", " – ", " - "]
        for sep in separators {
            if let range = rest.range(of: sep) {
                let kind = String(rest[rest.startIndex..<range.lowerBound])
                let title = String(rest[range.upperBound...])
                return Header(
                    timestamp: timestamp,
                    kind: kind.trimmingCharacters(in: .whitespaces),
                    title: title.trimmingCharacters(in: .whitespaces)
                )
            }
        }
        // No separator — treat the whole remainder as the title with unknown kind.
        return Header(
            timestamp: timestamp,
            kind: "operation",
            title: rest.trimmingCharacters(in: .whitespaces)
        )
    }

    private static func splitBody(_ lines: [String]) -> (rationale: String, changes: [WikiLogEntry.ChangeRef]) {
        var rationaleLines: [String] = []
        var changes: [WikiLogEntry.ChangeRef] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let change = parseChangeLine(trimmed) {
                changes.append(change)
            } else {
                rationaleLines.append(line)
            }
        }
        let rationale = rationaleLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (rationale, changes)
    }

    /// Matches `- verb \`path\`` rows produced by `WikiLogWriter.formatEntry`.
    private static func parseChangeLine(_ line: String) -> WikiLogEntry.ChangeRef? {
        guard line.hasPrefix("- ") else { return nil }
        let content = line.dropFirst(2)
        guard let spaceIdx = content.firstIndex(of: " ") else { return nil }
        let verb = String(content[content.startIndex..<spaceIdx]).lowercased()
        guard ["create", "modify", "delete"].contains(verb) else { return nil }
        var pathPart = content[content.index(after: spaceIdx)...]
        if pathPart.hasPrefix("`"), pathPart.hasSuffix("`"), pathPart.count >= 2 {
            pathPart = pathPart.dropFirst().dropLast()
        }
        let path = String(pathPart).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        return WikiLogEntry.ChangeRef(verb: verb, path: path)
    }
}
