import SwiftUI
import ClearlyCore

/// Apple-Notes-style row: bold title (first line or filename), quiet subtitle
/// with smart relative date + filename. Mirrors `FileListRowContent` on iOS
/// but uses a raw `URL` + modified-`Date?` pair instead of iOS `VaultFile`.
struct MacFileListRow: View {
    let url: URL
    let modified: Date?
    /// When this row is the active document, the workspace's in-memory text
    /// so title/preview reflect unsaved edits in real time.
    let liveText: String?

    @State private var snippet: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(titleText)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(subtitleText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 2)
        .task(id: modified) {
            await loadSnippet()
        }
    }

    // MARK: - Derivation

    private var filenameStem: String {
        url.deletingPathExtension().lastPathComponent
    }

    private var titleText: String {
        if let firstLine = extractFirstLineTitle(from: textForDisplay), !firstLine.isEmpty {
            return firstLine
        }
        return filenameStem
    }

    private var subtitleText: String {
        guard let modified else { return url.lastPathComponent }
        return "\(Self.smartDate(modified)) · \(url.lastPathComponent)"
    }

    private var textForDisplay: String? {
        liveText ?? snippet
    }

    // MARK: - Snippet loading

    private func loadSnippet() async {
        let fileURL = url
        let loaded: String? = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            let trimmed = Self.stripFrontmatter(text)
            let cap = 140
            if trimmed.count <= cap { return trimmed }
            let endIdx = trimmed.index(trimmed.startIndex, offsetBy: cap)
            return String(trimmed[..<endIdx]) + "\u{2026}"
        }.value
        await MainActor.run { snippet = loaded }
    }

    // MARK: - Title extraction

    private func extractFirstLineTitle(from text: String?) -> String? {
        guard let text else { return nil }
        let stripped = Self.stripFrontmatter(text)
        for raw in stripped.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("#") {
                let withoutHashes = String(trimmed.drop(while: { $0 == "#" }))
                let cleaned = withoutHashes.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? nil : cleaned
            }
            return trimmed
        }
        return nil
    }

    // MARK: - Static helpers

    private static func stripFrontmatter(_ text: String) -> String {
        guard text.hasPrefix("---") else { return text }
        var lines = text.components(separatedBy: "\n")
        guard lines.first == "---" else { return text }
        lines.removeFirst()
        if let closeIdx = lines.firstIndex(of: "---") {
            lines.removeSubrange(0...closeIdx)
            return lines.joined(separator: "\n")
        }
        return text
    }

    /// Notes.app-style relative date: time today, "Yesterday", weekday this
    /// week, month-day this year, short date older.
    private static func smartDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return timeFormatter.string(from: date)
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday"
        }
        if let daysAgo = cal.dateComponents([.day], from: date, to: Date()).day,
           daysAgo >= 0, daysAgo < 7 {
            return weekdayFormatter.string(from: date)
        }
        let nowYear = cal.component(.year, from: Date())
        let dateYear = cal.component(.year, from: date)
        return nowYear == dateYear
            ? dateThisYearFormatter.string(from: date)
            : dateOlderFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.timeStyle = .short
        df.dateStyle = .none
        return df
    }()

    private static let weekdayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "EEEE"
        return df
    }()

    private static let dateThisYearFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateFormat = "MMM d"
        return df
    }()

    private static let dateOlderFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.dateStyle = .short
        df.timeStyle = .none
        return df
    }()
}
