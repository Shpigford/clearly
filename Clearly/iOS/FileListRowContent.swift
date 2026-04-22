#if os(iOS)
import SwiftUI
import ClearlyCore

/// Notes.app-style row for a vault file: bold title pulled from the
/// document's first line (heading or otherwise), a quiet `smart-date ·
/// filename` subtitle, and a lazily-loaded ~140-char preview snippet
/// behind the scenes. Pure content — no Button wrapper, no tap handling,
/// no alerts. The parent List owns selection / swipe / context-menu
/// modifiers so SwiftUI applies its native row chrome.
///
/// Used by the iPad 3-column file list and the iPhone drilled-in folder
/// file list — same component, same brand.
struct FileListRowContent: View {
    let file: VaultFile
    /// In-memory text from the active document's session. Non-nil only when
    /// this row IS the active document; the row reads `liveText` instead of
    /// the disk-loaded snippet so the title/preview reflect unsaved typing
    /// in real time. Nil for all other rows — they fall back to the cached
    /// disk read.
    let liveText: String?

    @State private var snippet: String?
    @State private var didLoad: Bool = false

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
        .task(id: file.modified) {
            await loadSnippet()
        }
    }

    private var filenameStem: String {
        let ext = (file.name as NSString).pathExtension.lowercased()
        if FileNode.markdownExtensions.contains(ext) {
            return (file.name as NSString).deletingPathExtension
        }
        return file.name
    }

    private var titleText: String {
        if let firstLine = extractFirstLineTitle(from: textForDisplay), !firstLine.isEmpty {
            return firstLine
        }
        return filenameStem
    }

    private var subtitleText: String {
        if file.isPlaceholder { return "Not yet downloaded" }
        guard let modified = file.modified else { return file.name }
        return "\(Self.smartDate(modified)) · \(file.name)"
    }

    private var textForDisplay: String? {
        liveText ?? snippet
    }

    /// Notes.app-style relative date formatting: time-only today, "Yesterday",
    /// weekday name within the last week, month/day this year, short date older.
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
        if nowYear == dateYear {
            return dateThisYearFormatter.string(from: date)
        }
        return dateOlderFormatter.string(from: date)
    }

    private func extractFirstLineTitle(from text: String?) -> String? {
        guard let text else { return nil }
        let stripped = stripFrontmatter(text)
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

    private func loadSnippet() async {
        guard !file.isPlaceholder else {
            didLoad = true
            return
        }
        let url = file.url
        let loaded: String? = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: url) else { return nil }
            guard let text = String(data: data, encoding: .utf8) else { return nil }
            let trimmed = stripFrontmatter(text)
            let cap = 140
            if trimmed.count <= cap { return trimmed }
            let endIdx = trimmed.index(trimmed.startIndex, offsetBy: cap)
            return String(trimmed[..<endIdx]) + "…"
        }.value
        await MainActor.run {
            snippet = loaded
            didLoad = true
        }
    }
}
#endif
