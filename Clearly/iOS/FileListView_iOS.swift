import SwiftUI
import ClearlyCore

/// iPhone drill-in file list. Pushed onto the `FolderListView_iOS` nav stack
/// when the user taps a folder row (or "All Notes"). Shows every file in
/// `folderURL`'s direct children (or the entire vault if `folderURL` is the
/// `All Notes` sentinel), rendered with the same Notes-style
/// `FileListRowContent` the iPad uses. Taps push to `RawTextDetailView_iOS`.
///
/// Rename / delete live here via swipe-actions + context-menu. New-note in
/// this folder via the `+` toolbar button — creates an `untitled.md` inside
/// this folder, pushes to detail, auto-focuses for typing.
struct FileListView_iOS: View {
    @Environment(VaultSession.self) private var session

    let folderURL: URL
    let allNotesSentinel: URL

    @State private var renameTarget: VaultFile?
    @State private var renameDraft: String = ""
    @State private var deleteTarget: VaultFile?
    @State private var operationError: String?

    var body: some View {
        Group {
            if displayedFiles.isEmpty && session.files.isEmpty && session.isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedFiles.isEmpty {
                emptyState
            } else {
                fileList
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .refreshable { session.refresh() }
        .alert("Rename note", isPresented: renameAlertBinding) {
            TextField("Name", text: $renameDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") { commitRename() }
        } message: {
            Text("Enter a new name (extension preserved).")
        }
        .confirmationDialog(
            deleteTarget.map { "Delete \u{201C}\($0.name)\u{201D}?" } ?? "",
            isPresented: deleteConfirmBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This can't be undone from within Clearly.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { operationError = nil }
        } message: {
            Text(operationError ?? "")
        }
    }

    // MARK: - Content

    private var fileList: some View {
        List {
            ForEach(displayedFiles) { file in
                NavigationLink(value: file) {
                    FileListRowContent(file: file, liveText: nil)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteTarget = file
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        beginRename(file)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
                .contextMenu {
                    Button {
                        beginRename(file)
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        deleteTarget = file
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } preview: {
                    FileRowPreviewCard(file: file)
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            isAllNotes ? "No notes yet" : "No notes in this folder",
            systemImage: "tray",
            description: Text("Tap + to create your first note here.")
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                createNewNote()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .accessibilityLabel("New note")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                session.isShowingQuickSwitcher = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Search notes")
        }
    }

    // MARK: - Derivation

    private var isAllNotes: Bool {
        folderURL.standardizedFileURL == allNotesSentinel.standardizedFileURL
    }

    private var navTitle: String {
        isAllNotes ? (session.currentVault?.displayName ?? "All Notes") : folderURL.lastPathComponent
    }

    private var displayedFiles: [VaultFile] {
        let sorted = session.files.sorted { lhs, rhs in
            (lhs.modified ?? .distantPast) > (rhs.modified ?? .distantPast)
        }
        if isAllNotes { return sorted }
        let target = folderURL.standardizedFileURL
        return sorted.filter { $0.url.deletingLastPathComponent().standardizedFileURL == target }
    }

    // MARK: - Rename / delete / create

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private func beginRename(_ file: VaultFile) {
        renameDraft = (file.name as NSString).deletingPathExtension
        renameTarget = file
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        let draft = renameDraft
        renameTarget = nil
        Task {
            do {
                try await session.renameFile(target, to: draft)
            } catch VaultSessionError.readFailed(let msg) {
                operationError = msg
            } catch {
                operationError = error.localizedDescription
            }
        }
    }

    private func commitDelete() {
        guard let target = deleteTarget else { return }
        deleteTarget = nil
        Task {
            do {
                try await session.deleteFile(target)
            } catch {
                operationError = error.localizedDescription
            }
        }
    }

    private func createNewNote() {
        guard session.currentVault != nil else { return }
        let parent: URL? = isAllNotes ? nil : folderURL
        Task {
            do {
                let file = try await session.createUntitledNote(in: parent)
                await MainActor.run {
                    session.navigationPath.append(file)
                    session.markRecent(file)
                }
            } catch {
                DiagnosticLog.log("[iPhone] createUntitledNote failed: \(error.localizedDescription)")
            }
        }
    }
}
