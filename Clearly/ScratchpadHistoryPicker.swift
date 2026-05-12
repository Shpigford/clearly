import SwiftUI

struct ScratchpadHistoryPicker: View {
    @Environment(ScratchpadManager.self) private var manager
    @Environment(ScratchpadStore.self) private var store

    @FocusState private var searchFocused: Bool
    @State private var query: String = ""
    @State private var selectedID: ScratchpadNote.ID?
    @State private var hoveredID: ScratchpadNote.ID?

    var onDismiss: () -> Void

    private var notes: [ScratchpadNote] {
        store.search(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            ScratchpadDivider()
            list
            ScratchpadDivider()
            footer
        }
        .frame(width: 400, height: 460)
        .onAppear {
            selectedID = manager.currentNoteID ?? notes.first?.id
            DispatchQueue.main.async { searchFocused = true }
        }
        .onKeyPress(.upArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            openSelected()
            return .handled
        }
        .onKeyPress(.delete) {
            deleteSelected()
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField("Search scratchpads", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit { openSelected() }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                if notes.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 1) {
                        ForEach(notes) { note in
                            ScratchpadHistoryRow(
                                note: note,
                                isCurrent: note.id == manager.currentNoteID,
                                isSelected: note.id == selectedID,
                                isHovered: note.id == hoveredID
                            )
                            .id(note.id)
                            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .onTapGesture {
                                selectedID = note.id
                                open(note)
                            }
                            .onHover { hovering in
                                if hovering { hoveredID = note.id }
                                else if hoveredID == note.id { hoveredID = nil }
                            }
                            .contextMenu {
                                Button("Open") { open(note) }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    manager.deleteNote(note)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
            }
            .onChange(of: selectedID) { _, newID in
                guard let id = newID else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "No scratchpads yet" : "No matches for “\(query)”")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 0) {
            Button {
                store.revealInFinder()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 10, weight: .medium))
                    Text("Reveal in Finder")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(notes.count) note\(notes.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Actions

    private func moveSelection(by delta: Int) {
        guard !notes.isEmpty else { selectedID = nil; return }
        let currentIdx = selectedID.flatMap { id in
            notes.firstIndex(where: { $0.id == id })
        } ?? -1
        let next = max(0, min(notes.count - 1, currentIdx + delta))
        selectedID = notes[next].id
    }

    private func openSelected() {
        if let id = selectedID, let note = notes.first(where: { $0.id == id }) {
            open(note)
        } else if let first = notes.first {
            open(first)
        }
    }

    private func deleteSelected() {
        guard let id = selectedID, let note = notes.first(where: { $0.id == id }) else { return }
        manager.deleteNote(note)
        selectedID = manager.currentNoteID
    }

    private func open(_ note: ScratchpadNote) {
        manager.select(note: note)
        onDismiss()
    }
}

// MARK: - Row

struct ScratchpadHistoryRow: View {
    let note: ScratchpadNote
    let isCurrent: Bool
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            indicator
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                if !note.preview.isEmpty {
                    Text(note.preview)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            Text(relativeTime)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(rowBackground)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var indicator: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 5, height: 5)
            .opacity(isCurrent ? 1 : 0)
            .frame(width: 6, alignment: .center)
    }

    @ViewBuilder
    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(backgroundFill)
    }

    private var backgroundFill: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor.opacity(0.14))
        }
        if isHovered {
            return AnyShapeStyle(Color.primary.opacity(0.05))
        }
        return AnyShapeStyle(Color.clear)
    }

    private var displayTitle: String {
        note.title.isEmpty ? ScratchpadNote.titlePlaceholder : note.title
    }

    private var relativeTime: String {
        Self.formatter.localizedString(for: note.lastOpenedAt, relativeTo: Date())
    }

    private static let formatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

// MARK: - Divider

private struct ScratchpadDivider: View {
    var body: some View {
        Rectangle()
            .fill(.separator.opacity(0.45))
            .frame(height: 0.5)
    }
}
