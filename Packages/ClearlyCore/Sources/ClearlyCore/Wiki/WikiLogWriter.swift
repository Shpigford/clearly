import Foundation

/// Appends an entry to a wiki vault's `log.md` after an operation is
/// accepted. The format is intentionally grep-friendly — Karpathy's canonical
/// sanity check `grep "^## \[" log.md | tail -5` continues to work, and
/// humans can scan the file top-to-bottom as a changelog.
public enum WikiLogWriter {

    public static let filename = "log.md"

    public enum WriteError: Error, Equatable, Sendable {
        case encodingFailure
    }

    /// Append `operation` as a dated section to `log.md`. Creates the file
    /// with a `# Log\n\n` header if it doesn't exist. Not transactional with
    /// the primary apply — a log-append failure is surfaced to the caller
    /// but doesn't roll back the already-applied changes.
    public static func appendOperation(_ operation: WikiOperation, to vaultRoot: URL) throws {
        let logURL = vaultRoot.appendingPathComponent(filename)
        let existing: String
        if FileManager.default.fileExists(atPath: logURL.path) {
            let data = try CoordinatedFileIO.read(at: logURL)
            existing = String(data: data, encoding: .utf8) ?? ""
        } else {
            existing = "# Log\n\n"
        }

        let entry = formatEntry(operation)
        let separator = existing.isEmpty
            ? ""
            : (existing.hasSuffix("\n\n") ? "" : (existing.hasSuffix("\n") ? "\n" : "\n\n"))
        let newContent = existing + separator + entry

        guard let data = newContent.data(using: .utf8) else {
            throw WriteError.encodingFailure
        }
        try CoordinatedFileIO.write(data, to: logURL)
    }

    /// Exposed for tests. Produces a single operation's log section.
    public static func formatEntry(_ op: WikiOperation) -> String {
        var lines: [String] = []
        lines.append("## [\(timestampFormatter.string(from: op.createdAt))] \(op.kind.rawValue) — \(op.title)")
        lines.append("")
        if !op.rationale.isEmpty {
            lines.append(op.rationale)
            lines.append("")
        }
        for change in op.changes {
            lines.append("- \(verb(for: change)) `\(change.path)`")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    private static func verb(for change: FileChange) -> String {
        switch change {
        case .create: return "create"
        case .modify: return "modify"
        case .delete: return "delete"
        }
    }
}
