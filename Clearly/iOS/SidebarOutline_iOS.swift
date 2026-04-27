#if os(iOS)
import SwiftUI
import ClearlyCore

/// Recursive folder + file outline used by both the iPhone (`FolderListView_iOS`)
/// and the iPad sidebar (`IPadRootView`). Mirrors the Mac sidebar's
/// `outlineNode` pattern: folders become `DisclosureGroup`s with persistent
/// expansion state, files render as tappable leaf rows. Empty folders render
/// as leaves so the disclosure indicator hides.
///
/// Actions (open, rename, delete, create) are pushed back to the host view
/// via callbacks so each platform can drive its own alert/confirmation chrome
/// without the outline owning that state.
struct SidebarOutline_iOS: View {
    let nodes: [FileNode]
    let onSelectFile: (VaultFile) -> Void
    let onRenameFile: (VaultFile) -> Void
    let onDeleteFile: (VaultFile) -> Void
    let onCreateFile: (URL) -> Void
    let onCreateFolder: (URL) -> Void

    @Environment(VaultSession.self) private var session
    @Environment(IOSExpansionState.self) private var expansion

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

    private func fileRow(_ node: FileNode) -> some View {
        let resolved = vaultFile(for: node)
        let title = node.url.deletingPathExtension().lastPathComponent
        return Label(title, systemImage: "doc.text")
            .contentShape(Rectangle())
            .onTapGesture { onSelectFile(resolved) }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    onDeleteFile(resolved)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    onRenameFile(resolved)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(.blue)
            }
            .contextMenu {
                Button {
                    onRenameFile(resolved)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    onDeleteFile(resolved)
                } label: {
                    Label("Delete", systemImage: "trash")
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
