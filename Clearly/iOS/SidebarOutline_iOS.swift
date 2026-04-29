#if os(iOS)
import SwiftUI
import ClearlyCore

/// Recursive folder + file outline used by both the iPhone (`FolderListView_iOS`)
/// and the iPad sidebar (`IPadRootView`). Mirrors the Mac sidebar's
/// `outlineNode` pattern: folders become `DisclosureGroup`s with persistent
/// expansion state, files render as tappable leaf rows. Empty folders render
/// as leaves so the disclosure indicator hides.
///
/// File actions (open, rename, delete, move, duplicate) are pushed back to the
/// host view via callbacks so each platform can drive its own sheet/dialog
/// chrome without the outline owning that state. Rename is the exception —
/// it edits inline within the row, so the outline owns just enough local
/// state to swap a `Label` for a `TextField` and report the new name on
/// commit.
struct SidebarOutline_iOS: View {
    let nodes: [FileNode]
    let onSelectFile: (VaultFile) -> Void
    let onRenameFile: (VaultFile, String) -> Void
    let onDeleteFile: (VaultFile) -> Void
    let onMoveFile: (VaultFile) -> Void
    let onDuplicateFile: (VaultFile) -> Void
    let onCreateFile: (URL) -> Void
    let onCreateFolder: (URL) -> Void

    @Environment(VaultSession.self) private var session
    @Environment(IOSExpansionState.self) private var expansion

    @State private var renamingURL: URL?
    @State private var renameDraft: String = ""
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        ForEach(nodes) { node in
            outlineRow(node)
        }
    }

    // MARK: - Recursive row

    /// `AnyView` is required for the recursive call: a `@ViewBuilder` returning
    /// `some View` would define its opaque type in terms of itself, which the
    /// type system rejects. Mac's `MacFolderSidebar.outlineNode` does the same.
    private func outlineRow(_ node: FileNode) -> AnyView {
        if let children = node.displayChildren {
            return AnyView(
                DisclosureGroup(isExpanded: expansion.expandedBinding(for: node.url)) {
                    ForEach(children) { child in
                        outlineRow(child)
                    }
                } label: {
                    folderLabel(node)
                        .contextMenu { folderMenu(folderURL: node.url) }
                }
            )
        } else if node.isDirectory {
            return AnyView(
                folderLabel(node)
                    .contextMenu { folderMenu(folderURL: node.url) }
            )
        } else {
            return AnyView(fileRow(node))
        }
    }

    // MARK: - Rows

    private func folderLabel(_ node: FileNode) -> some View {
        Label(node.name, systemImage: "folder")
    }

    @ViewBuilder
    private func fileRow(_ node: FileNode) -> some View {
        let resolved = vaultFile(for: node)
        if renamingURL == node.url {
            renameRow(for: resolved)
        } else {
            displayRow(for: resolved, node: node)
        }
    }

    private func displayRow(for file: VaultFile, node: FileNode) -> some View {
        let title = node.url.deletingPathExtension().lastPathComponent
        return Label(title, systemImage: "doc.text")
            .contentShape(Rectangle())
            .onTapGesture { onSelectFile(file) }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    onDeleteFile(file)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    beginInlineRename(file)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(.blue)
            }
            .contextMenu {
                Button {
                    beginInlineRename(file)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    onMoveFile(file)
                } label: {
                    Label("Move\u{2026}", systemImage: "folder")
                }
                Button {
                    onDuplicateFile(file)
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                ShareLink(item: file.url)
                Divider()
                Button(role: .destructive) {
                    onDeleteFile(file)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    private func renameRow(for file: VaultFile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            TextField("Name", text: $renameDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($renameFieldFocused)
                .onSubmit { commitInlineRename(file) }
        }
        .onChange(of: renameFieldFocused) { _, isFocused in
            // Commit on focus loss (tap outside, swipe away). Guard against
            // late callbacks after the row already committed and cleared
            // `renamingURL`.
            if !isFocused, renamingURL == file.url {
                commitInlineRename(file)
            }
        }
    }

    @ViewBuilder
    private func folderMenu(folderURL: URL) -> some View {
        Button {
            onCreateFile(folderURL)
        } label: {
            Label("New File", systemImage: "doc.badge.plus")
        }
        Button {
            onCreateFolder(folderURL)
        } label: {
            Label("New Folder", systemImage: "folder.badge.plus")
        }
    }

    // MARK: - Inline rename

    private func beginInlineRename(_ file: VaultFile) {
        renameDraft = (file.name as NSString).deletingPathExtension
        renamingURL = file.url
        // Defer focus so the TextField has been laid out before the keyboard
        // raises — without the dispatch the focus often loses to the row's
        // tap gesture in compact layouts.
        DispatchQueue.main.async {
            renameFieldFocused = true
        }
    }

    private func commitInlineRename(_ file: VaultFile) {
        let draft = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = (file.name as NSString).deletingPathExtension
        renamingURL = nil
        renameFieldFocused = false
        renameDraft = ""
        guard !draft.isEmpty, draft != original else { return }
        onRenameFile(file, draft)
    }

    // MARK: - VaultFile lookup

    /// Resolve the live `VaultFile` matching this tree node. Falls back to a
    /// synthesized record when the watcher hasn't observed the file yet (e.g.
    /// brand-new file the user just created) so taps don't get swallowed.
    private func vaultFile(for node: FileNode) -> VaultFile {
        let target = node.url.standardizedFileURL
        if let match = session.files.first(where: { $0.url.standardizedFileURL == target }) {
            return match
        }
        return VaultFile(url: node.url, name: node.name, modified: nil, isPlaceholder: false)
    }
}
#endif
