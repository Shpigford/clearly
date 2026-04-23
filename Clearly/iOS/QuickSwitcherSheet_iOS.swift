import SwiftUI
import ClearlyCore

struct QuickSwitcherSheet_iOS: View {
    @Environment(VaultSession.self) private var vault
    @Environment(\.dismiss) private var dismiss

    /// How a picked file is surfaced. iPhone replaces `VaultSession.navigationPath`
    /// with `[file]`; iPad routes through `IPadTabController.openOrActivate`. The
    /// closure is responsible for both navigation AND `markRecent` so the switcher
    /// doesn't have to know which model it's driving.
    let onOpenFile: (VaultFile) -> Void

    @State private var query: String = ""
    @State private var rows: [QuickSwitcherRow] = []

    private static let filenameLimit = 20
    private static let contentLimit = 30

    var body: some View {
        NavigationStack {
            list
                .navigationTitle("Jump to Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Cancel") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
                .searchable(
                    text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Jump to or create a note"
                )
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit(of: .search) { openFirstRow() }
                .submitLabel(.go)
        }
        .onAppear {
            recomputeRows()
        }
        .onChange(of: query) { _, _ in recomputeRows() }
        .onChange(of: vault.files) { _, _ in recomputeRows() }
    }

    @ViewBuilder
    private var list: some View {
        if rows.isEmpty {
            ContentUnavailableView(
                query.isEmpty ? "No Recent Notes" : "No Matches",
                systemImage: query.isEmpty ? "clock" : "magnifyingglass",
                description: Text(query.isEmpty
                    ? "Notes you open will show up here."
                    : "Try a different query.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if query.isEmpty && !rows.isEmpty {
                    Section("Recent") {
                        ForEach(rows) { row in rowView(row) }
                    }
                } else {
                    ForEach(rows) { row in rowView(row) }
                }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func rowView(_ row: QuickSwitcherRow) -> some View {
        Button { open(row) } label: {
            switch row {
            case .recent(let file):
                fileRow(
                    icon: file.isPlaceholder ? "icloud.and.arrow.down" : "doc.text",
                    title: AttributedString(file.name),
                    subtitle: nil
                )
            case .filename(let file, let ranges):
                fileRow(
                    icon: file.isPlaceholder ? "icloud.and.arrow.down" : "doc.text",
                    title: highlighted(file.name, ranges: ranges),
                    subtitle: nil
                )
            case .content(let file, let snippet, let lineNumber):
                fileRow(
                    icon: "text.alignleft",
                    title: AttributedString(file.name),
                    subtitle: snippet.map { formatSnippet($0, line: lineNumber) }
                )
            case .create(let name):
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.tint)
                        .frame(width: 24)
                    Text("Create “\(name)”")
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
    }

    private func fileRow(icon: String, title: AttributedString, subtitle: AttributedString?) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    // MARK: - Row computation

    private func recomputeRows() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if !vault.recentFiles.isEmpty {
                rows = vault.recentFiles.map { .recent($0) }
            } else {
                // No opened-history yet: show everything sorted by mtime
                // descending so the sheet is useful on a fresh vault. Most
                // recently touched files float to the top — same sort as
                // the iPad file column.
                let sorted = vault.files.sorted { lhs, rhs in
                    (lhs.modified ?? .distantPast) > (rhs.modified ?? .distantPast)
                }
                rows = sorted.prefix(Self.filenameLimit).map { .recent($0) }
            }
            return
        }

        var filenameMatches: [(file: VaultFile, score: Int, ranges: [Range<String.Index>])] = []
        for file in vault.files {
            if let result = FuzzyMatcher.match(query: trimmed, target: file.name) {
                filenameMatches.append((file, result.score, result.matchedRanges))
            }
        }
        filenameMatches.sort { $0.score > $1.score }
        if filenameMatches.count > Self.filenameLimit {
            filenameMatches = Array(filenameMatches.prefix(Self.filenameLimit))
        }

        var contentHits: [QuickSwitcherRow] = []
        if trimmed.count >= 2, let index = vault.currentIndex {
            let filenameURLs = Set(filenameMatches.map { $0.file.url.standardizedFileURL })
            let vaultRoot = vault.currentVault?.url ?? index.rootURL
            let byURL = Dictionary(uniqueKeysWithValues: vault.files.map {
                ($0.url.standardizedFileURL, $0)
            })
            let groups = index.searchFilesGrouped(query: trimmed)
            for group in groups {
                let absoluteURL = vaultRoot.appendingPathComponent(group.file.path).standardizedFileURL
                guard !filenameURLs.contains(absoluteURL) else { continue }
                let file = byURL[absoluteURL] ?? VaultFile(
                    url: absoluteURL,
                    name: group.file.filename,
                    modified: group.file.modifiedAt,
                    isPlaceholder: false
                )
                let excerpt = group.excerpts.first
                contentHits.append(.content(
                    file,
                    snippet: excerpt?.highlightedContextLine.trimmingCharacters(in: .whitespaces),
                    lineNumber: excerpt?.lineNumber
                ))
                if contentHits.count >= Self.contentLimit { break }
            }
        }

        var combined: [QuickSwitcherRow] = filenameMatches.map {
            .filename($0.file, ranges: $0.ranges)
        }
        combined.append(contentsOf: contentHits)

        if combined.isEmpty {
            combined.append(.create(name: createName(for: trimmed)))
        }
        rows = combined
    }

    // MARK: - Interaction

    private func openFirstRow() {
        guard let row = rows.first else { return }
        open(row)
    }

    private func open(_ row: QuickSwitcherRow) {
        switch row {
        case .recent(let file), .filename(let file, _), .content(let file, _, _):
            dismiss()
            navigate(to: file)
        case .create(let name):
            let target = name
            dismiss()
            Task {
                do {
                    let file = try await vault.openOrCreate(name: target)
                    await MainActor.run { navigate(to: file) }
                } catch {
                    DiagnosticLog.log("Quick switcher create failed for \(target): \(error)")
                }
            }
        }
    }

    private func navigate(to file: VaultFile) {
        onOpenFile(file)
    }

    // MARK: - Formatting helpers

    private func highlighted(_ text: String, ranges: [Range<String.Index>]) -> AttributedString {
        var attributed = AttributedString(text)
        for range in ranges {
            guard let attrRange = Range(range, in: attributed) else { continue }
            attributed[attrRange].foregroundColor = .accentColor
            attributed[attrRange].font = .body.bold()
        }
        return attributed
    }

    /// Parse FTS5 `<<match>>` delimiters out of the snippet and produce an AttributedString
    /// with the matched runs highlighted.
    private func formatSnippet(_ raw: String, line: Int?) -> AttributedString {
        var plain = ""
        var highlightRanges: [Range<String.Index>] = []
        var inHighlight = false
        var current = raw.startIndex
        while current < raw.endIndex {
            if raw[current...].hasPrefix("<<") {
                inHighlight = true
                current = raw.index(current, offsetBy: 2)
                continue
            }
            if raw[current...].hasPrefix(">>") {
                inHighlight = false
                current = raw.index(current, offsetBy: 2)
                continue
            }
            let insertedStart = plain.endIndex
            plain.append(raw[current])
            if inHighlight {
                let insertedEnd = plain.endIndex
                if let last = highlightRanges.last, last.upperBound == insertedStart {
                    highlightRanges[highlightRanges.count - 1] = last.lowerBound..<insertedEnd
                } else {
                    highlightRanges.append(insertedStart..<insertedEnd)
                }
            }
            current = raw.index(after: current)
        }

        var out = AttributedString(plain)
        for range in highlightRanges {
            guard let attrRange = Range(range, in: out) else { continue }
            out[attrRange].foregroundColor = .accentColor
            out[attrRange].font = .footnote.bold()
        }
        if let line {
            out.append(AttributedString(" · line \(line)"))
        }
        return out
    }

    /// Turn the user's query into the filename we'll create. Runs through the
    /// same kebab-case sanitization as manual renames and Notes-style
    /// auto-naming so filenames across the app stay consistent.
    private func createName(for query: String) -> String {
        var stem = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if stem.lowercased().hasSuffix(".md") {
            stem = String(stem.dropLast(3))
        }
        let sanitized = UntitledRename.sanitizeFilename(stem)
        guard !sanitized.isEmpty else { return "untitled.md" }
        return "\(sanitized).md"
    }
}

/// Hidden buttons that register the ⌘K / ⌘⇧F shortcuts. Place in `.background { ... }`
/// at each top-level iOS destination (sidebar, detail) so the shortcut fires regardless
/// of which view owns focus on a hardware keyboard.
///
/// Uses `.hidden()` rather than a zero-size / opacity-0 ZStack: `.hidden()` keeps the
/// view in the layout (so the shortcut stays registered) while removing it from both
/// visual rendering and the accessibility tree. `.disabled` gates the shortcut when no
/// vault is attached so stray hits don't open an inert sheet.
struct QuickSwitcherShortcuts: View {
    @Environment(VaultSession.self) private var session

    var body: some View {
        ZStack {
            Color.clear
            Button("Quick Switcher") {
                session.isShowingQuickSwitcher = true
            }
            .keyboardShortcut("k", modifiers: .command)
            .hidden()

            Button("Global Search") {
                session.isShowingQuickSwitcher = true
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .hidden()
        }
        .accessibilityHidden(true)
        .disabled(session.currentVault == nil)
    }
}

enum QuickSwitcherRow: Identifiable {
    case recent(VaultFile)
    case filename(VaultFile, ranges: [Range<String.Index>])
    case content(VaultFile, snippet: String?, lineNumber: Int?)
    case create(name: String)

    var id: String {
        switch self {
        case .recent(let f): return "recent-\(f.id)"
        case .filename(let f, _): return "fn-\(f.id)"
        case .content(let f, _, _): return "ct-\(f.id)"
        case .create(let n): return "create-\(n)"
        }
    }
}
