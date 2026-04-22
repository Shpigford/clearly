import SwiftUI
import ClearlyCore

/// Middle column — Apple-Notes-style list of markdown files inside the
/// folder currently selected in the sidebar. Sorted by modified date
/// descending so recent edits float to the top.
struct MacNotesListColumn: View {
    @Bindable var workspace: WorkspaceManager
    let selection: SidebarSelection?

    @Binding var selectedFileURL: URL?
    @Binding var searchQuery: String

    @State private var renameTarget: URL?
    @State private var renameDraft: String = ""
    @State private var deleteTarget: URL?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if workspace.locations.isEmpty {
                ContentUnavailableView(
                    "No Vault",
                    systemImage: "folder",
                    description: Text("Add a folder from the sidebar to get started.")
                )
            } else if selection == nil {
                ContentUnavailableView(
                    "Choose a folder",
                    systemImage: "sidebar.left",
                    description: Text("Pick a folder in the sidebar to see its notes.")
                )
            } else if filteredFiles.isEmpty {
                ContentUnavailableView(
                    searchQuery.isEmpty ? "No Notes" : "No Matches",
                    systemImage: searchQuery.isEmpty ? "tray" : "magnifyingglass",
                    description: Text(searchQuery.isEmpty
                        ? "Create your first note with ⌘N."
                        : "Try a different search.")
                )
            } else {
                notesList
            }
        }
        .navigationTitle(columnTitle)
        .toolbar { columnToolbar }
        .alert("Rename Note", isPresented: renameAlertBinding) {
            TextField("Name", text: $renameDraft)
                .textFieldStyle(.roundedBorder)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") { commitRename() }
        }
        .alert(
            deleteTarget.map { "Delete \u{201C}\($0.deletingPathExtension().lastPathComponent)\u{201D}?" } ?? "Delete?",
            isPresented: deleteAlertBinding
        ) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This can't be undone from within Clearly.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - List body

    private var notesList: some View {
        List(selection: $selectedFileURL) {
            ForEach(filteredFiles, id: \.url) { file in
                MacFileListRow(url: file.url, modified: file.modified, liveText: liveTextFor(file.url))
                    .tag(file.url)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deleteTarget = file.url
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            beginRename(file.url)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.blue)
                        Button {
                            workspace.togglePin(file.url)
                        } label: {
                            Label(workspace.isPinned(file.url) ? "Unpin" : "Pin", systemImage: "pin")
                        }
                        .tint(.yellow)
                    }
                    .contextMenu {
                        Button("Open", systemImage: "doc") {
                            workspace.openFile(at: file.url)
                        }
                        Button("Open in New Tab", systemImage: "plus.rectangle.on.rectangle") {
                            workspace.openFileInNewTab(at: file.url)
                        }
                        Divider()
                        Button("Rename", systemImage: "pencil") {
                            beginRename(file.url)
                        }
                        Button(workspace.isPinned(file.url) ? "Unpin" : "Pin",
                               systemImage: workspace.isPinned(file.url) ? "pin.slash" : "pin") {
                            workspace.togglePin(file.url)
                        }
                        Button("Reveal in Finder", systemImage: "folder") {
                            NSWorkspace.shared.activateFileViewerSelecting([file.url])
                        }
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            deleteTarget = file.url
                        }
                    }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var columnToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                workspace.createUntitledDocument()
            } label: {
                Label("New Note", systemImage: "square.and.pencil")
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("New Note")
        }
    }

    // MARK: - Derivation

    private var columnTitle: String {
        switch selection {
        case .allNotes(let locationID):
            return workspace.locations.first(where: { $0.id == locationID })?.name ?? "Notes"
        case .folder(let url):
            return url.lastPathComponent
        case .none:
            return "Notes"
        }
    }

    private var filteredFiles: [FileEntry] {
        let all = filesForSelection()
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered: [FileEntry]
        if query.isEmpty {
            filtered = all
        } else {
            filtered = all.filter { $0.url.lastPathComponent.lowercased().contains(query) }
        }
        return filtered.sorted { (lhs, rhs) in
            (lhs.modified ?? .distantPast) > (rhs.modified ?? .distantPast)
        }
    }

    private func filesForSelection() -> [FileEntry] {
        switch selection {
        case .allNotes(let locationID):
            guard let location = workspace.locations.first(where: { $0.id == locationID }) else { return [] }
            return Self.flatten(tree: location.fileTree)
        case .folder(let folderURL):
            guard let node = Self.findNode(url: folderURL, in: workspace.locations) else { return [] }
            return Self.flatten(tree: node.children ?? [])
        case .none:
            return []
        }
    }

    private func liveTextFor(_ url: URL) -> String? {
        if workspace.currentFileURL == url { return workspace.currentFileText }
        return nil
    }

    // MARK: - Row actions

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private func beginRename(_ url: URL) {
        renameTarget = url
        renameDraft = url.deletingPathExtension().lastPathComponent
    }

    private func commitRename() {
        guard let oldURL = renameTarget else { return }
        defer { renameTarget = nil }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let ext = oldURL.pathExtension.isEmpty ? "md" : oldURL.pathExtension
        let newName = trimmed.hasSuffix(".\(ext)") ? trimmed : "\(trimmed).\(ext)"
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
            for id in workspace.locations.map(\.id) {
                workspace.refreshTree(for: id)
            }
            if workspace.currentFileURL == oldURL {
                workspace.openFile(at: newURL)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitDelete() {
        guard let url = deleteTarget else { return }
        defer { deleteTarget = nil }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            for id in workspace.locations.map(\.id) {
                workspace.refreshTree(for: id)
            }
            if workspace.currentFileURL == url {
                if let id = workspace.activeDocumentID {
                    workspace.closeDocument(id)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Static helpers

    struct FileEntry: Equatable {
        let url: URL
        let modified: Date?
    }

    private static func flatten(tree: [FileNode]) -> [FileEntry] {
        var out: [FileEntry] = []
        for node in tree {
            if node.isDirectory {
                out.append(contentsOf: flatten(tree: node.children ?? []))
            } else {
                out.append(FileEntry(url: node.url, modified: modifiedDate(node.url)))
            }
        }
        return out
    }

    private static func findNode(url target: URL, in locations: [BookmarkedLocation]) -> FileNode? {
        for location in locations {
            if let hit = walk(location.fileTree, target: target) { return hit }
        }
        return nil
    }

    private static func walk(_ nodes: [FileNode], target: URL) -> FileNode? {
        for node in nodes {
            if node.url == target { return node }
            if let children = node.children, let hit = walk(children, target: target) {
                return hit
            }
        }
        return nil
    }

    private static func modifiedDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
