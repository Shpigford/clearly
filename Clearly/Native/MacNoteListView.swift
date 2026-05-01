import SwiftUI
import AppKit
import ClearlyCore

/// Notes-style middle pane for the 3-pane layout. Renders an `NoteSummary`
/// list pulled from `VaultIndex.summaries(...)`, sorted per the user's
/// `noteListSortOrder` and filtered to either recursive or flat mode per
/// the per-folder `isFolderRecursive` flag. Selection is bidirectionally
/// bound to the workspace's active document via the parent's
/// `selectedNoteURL` binding — clicking a row opens the note in the
/// active tab.
///
/// Reload triggers:
/// - `selectedFolderURL` change (user picks a different folder)
/// - `vaultIndexRevision` bump (a re-index just landed)
/// - `treeRevision` bump (filesystem watcher saw a change)
/// - sort order or recursion toggle change
/// - locations list change (vault added / removed)
struct MacNoteListView: View {
    @Bindable var workspace: WorkspaceManager
    @Binding var selectedNoteURL: URL?

    @State private var summaries: [NoteSummary] = []
    @State private var isLoading = false
    @State private var reloadToken = 0
    @State private var pendingFSBump: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 240)
        .task(id: reloadKey) { await reload() }
        // User-driven changes reload immediately so the UI feels snappy.
        .onChange(of: workspace.selectedFolderURL) { _, _ in bump() }
        .onChange(of: workspace.locations.map(\.id)) { _, _ in bump() }
        .onChange(of: workspace.noteListSortOrder) { _, _ in bump() }
        .onChange(of: workspace.nonRecursiveFolders) { _, _ in bump() }
        // Filesystem revisions tick on every autosave + every reindex pass —
        // debounce them so a burst of writes coalesces into one reload
        // instead of N full SQL queries running back-to-back.
        .onChange(of: workspace.treeRevision) { _, _ in debouncedBump() }
        .onChange(of: workspace.vaultIndexRevision) { _, _ in debouncedBump() }
        .onDisappear { pendingFSBump?.cancel() }
    }

    private var reloadKey: Int { reloadToken }

    private func bump() {
        pendingFSBump?.cancel()
        pendingFSBump = nil
        reloadToken &+= 1
    }

    private func debouncedBump() {
        pendingFSBump?.cancel()
        pendingFSBump = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            reloadToken &+= 1
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if let folder = effectiveFolder {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(noteCountLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                recursionToggle(folder: folder)
                sortMenu
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        } else {
            HStack {
                Text("No folder selected")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var noteCountLabel: String {
        let count = summaries.count
        return count == 1 ? "1 Note" : "\(count) Notes"
    }

    @ViewBuilder
    private func recursionToggle(folder: URL) -> some View {
        let isRecursive = workspace.isFolderRecursive(folder)
        Button {
            workspace.setFolderRecursive(!isRecursive, for: folder)
        } label: {
            Image(systemName: isRecursive
                  ? "rectangle.stack.fill"
                  : "rectangle")
                .imageScale(.medium)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(isRecursive
              ? "Showing notes from subfolders. Click to show this folder only."
              : "Showing this folder only. Click to include subfolders.")
        .accessibilityLabel(isRecursive
                            ? "Showing notes from subfolders"
                            : "Showing this folder only")
    }

    private var sortMenu: some View {
        Menu {
            ForEach(NoteListSortOrder.allCases) { order in
                Button {
                    workspace.setNoteListSortOrder(order)
                } label: {
                    HStack {
                        Text(order.displayName)
                        Spacer()
                        if workspace.noteListSortOrder == order {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .imageScale(.medium)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22)
        .help("Sort order: \(workspace.noteListSortOrder.displayName)")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if effectiveFolder == nil {
            ContentUnavailableView(
                "Select a folder",
                systemImage: "folder",
                description: Text("Click a folder in the sidebar to see its notes here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoading && summaries.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if summaries.isEmpty {
            ContentUnavailableView(
                "No notes",
                systemImage: "doc.text",
                description: Text("This folder has no markdown notes yet.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(summaries, selection: $selectedNoteURL) { note in
                NoteListRow(note: note)
                    .tag(note.url)
                    .listRowSeparator(.visible)
            }
            .listStyle(.inset)
        }
    }

    // MARK: - Folder + summaries resolution

    /// Falls back to the first location when the user has not yet picked a
    /// folder, so the middle pane is never blank on first entry to 3-pane
    /// mode (assuming at least one vault is registered).
    private var effectiveFolder: URL? {
        workspace.selectedFolderURL ?? workspace.locations.first?.url
    }

    @MainActor
    private func reload() async {
        guard let folder = effectiveFolder else {
            summaries = []
            return
        }
        guard let (index, relativePath) = workspace.vaultIndexAndRelativePath(for: folder) else {
            // Folder lives outside every registered vault — show empty
            // rather than crashing or surfacing a half-broken state.
            summaries = []
            return
        }

        // Snapshot every input that gates assignment. The previous folder-
        // equality check missed sort/recursion changes — toggling sort
        // while a query was in flight could flash rows from the old order.
        let recursive = workspace.isFolderRecursive(folder)
        let sort = workspace.noteListSortOrder
        isLoading = summaries.isEmpty
        defer { isLoading = false }

        // Run the SQL off the main thread, but tie its cancellation to the
        // parent's task scope. `.task(id: reloadKey)` cancels this whole
        // function when `reloadToken` bumps, so any in-flight detached
        // query gets cancelled too instead of running to completion and
        // racing against the new query for the assignment slot.
        let detached = Task.detached(priority: .userInitiated) {
            index.summaries(folderRelativePath: relativePath, recursive: recursive, sort: sort)
        }
        let result = await withTaskCancellationHandler {
            await detached.value
        } onCancel: {
            detached.cancel()
        }

        // After the await `Task.isCancelled` is the only honest signal —
        // the awaited value still arrives even when cancelled because
        // `index.summaries` doesn't itself check for cancellation.
        guard !Task.isCancelled else { return }
        summaries = result
    }
}

// MARK: - Row

private struct NoteListRow: View {
    let note: NoteSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.dateLabel(for: note.modifiedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
                if !note.preview.isEmpty {
                    Text(note.preview)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private static func dateLabel(for date: Date) -> String {
        if date == .distantPast { return "—" }
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday"
        }
        let now = Date()
        if let weekAgo = cal.date(byAdding: .day, value: -6, to: now), date >= weekAgo {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}
