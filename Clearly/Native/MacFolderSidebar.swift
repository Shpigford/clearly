import SwiftUI
import ClearlyCore

/// Native Apple-Notes-style left sidebar. Two-column shell — folders and
/// files are both rendered as rows in this outline. Folders use
/// `DisclosureGroup` to expand/collapse; files use `doc.text` leaf rows
/// whose selection opens them in the detail column.
struct MacFolderSidebar: View {
    @Bindable var workspace: WorkspaceManager
    @Binding var selectedFileURL: URL?

    var body: some View {
        List(selection: $selectedFileURL) {
            if !workspace.pinnedFiles.isEmpty {
                pinnedSection
            }

            ForEach(workspace.locations) { location in
                locationSection(location)
            }

            if workspace.locations.isEmpty {
                ContentUnavailableView(
                    "No Vault",
                    systemImage: "folder.badge.plus",
                    description: Text("Add a folder to get started.")
                )
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.sidebar)
        .environment(\.sidebarRowSize, .small)
        .tint(Color.primary.opacity(0.12))
        .transaction { $0.disablesAnimations = true }
        .toolbar { sidebarToolbar }
    }

    // MARK: - Pinned

    private var pinnedSection: some View {
        Section {
            ForEach(workspace.pinnedFiles, id: \.self) { url in
                Text(url.deletingPathExtension().lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .tag(url)
                    .contextMenu {
                        Button("Unpin", systemImage: "pin.slash") {
                            workspace.togglePin(url)
                        }
                        Button("Open in New Tab", systemImage: "plus.rectangle.on.rectangle") {
                            workspace.openFileInNewTab(at: url)
                        }
                        Divider()
                        Button("Reveal in Finder", systemImage: "folder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
            }
        } header: {
            sectionHeader(title: "Pinned", systemImage: "pin")
        }
    }

    // MARK: - Location section

    private func locationSection(_ location: BookmarkedLocation) -> some View {
        Section {
            OutlineGroup(topLevelNodes(in: location.fileTree), children: \.outlineChildren) { node in
                outlineRow(node: node)
            }
        } header: {
            sectionHeader(title: location.name, systemImage: "folder")
        }
    }

    /// Custom section header — SwiftUI's default `Label` spaces icon and text
    /// with a wide gap in sidebar sections. Swap in an `HStack` with a tight
    /// spacing so the icon sits snug next to the label.
    private func sectionHeader(title: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(title)
        }
    }

    @ViewBuilder
    private func outlineRow(node: FileNode) -> some View {
        if node.isDirectory {
            Label(node.name, systemImage: "folder")
                .contextMenu { folderContextMenu(url: node.url) }
        } else {
            fileRow(url: node.url, icon: "doc.text")
                .tag(node.url)
        }
    }

    // MARK: - Rows

    /// Pinned rows render `pin.fill` with the accent tint; file leaves render
    /// `doc.text` in secondary. Both use `.tint` / `HierarchicalShapeStyle`
    /// so the sidebar's built-in selection handling flips them to white on
    /// the selected row instantly — no manual comparison to `selectedFileURL`
    /// needed (that path adds a one-frame delay because the binding updates
    /// through `onChange` rather than the row's view identity).
    private func fileRow(url: URL, icon: String) -> some View {
        Label(url.deletingPathExtension().lastPathComponent, systemImage: icon)
            .lineLimit(1)
            .truncationMode(.middle)
            .contextMenu {
                Button(workspace.isPinned(url) ? "Unpin" : "Pin",
                       systemImage: workspace.isPinned(url) ? "pin.slash" : "pin") {
                    workspace.togglePin(url)
                }
                Button("Open in New Tab", systemImage: "plus.rectangle.on.rectangle") {
                    workspace.openFileInNewTab(at: url)
                }
                Divider()
                Button("Reveal in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
    }

    @ViewBuilder
    private func folderContextMenu(url: URL) -> some View {
        Button("Reveal in Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                workspace.showOpenPanel()
            } label: {
                Label("Add Vault", systemImage: "folder.badge.plus")
            }
            .help("Add a vault folder")
        }
    }

    // MARK: - Derivation

    /// Top-level nodes of a vault — folders plus loose markdown files in the root.
    private func topLevelNodes(in tree: [FileNode]) -> [FileNode] {
        tree.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory // folders first
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

private extension FileNode {
    /// Children accessor for `OutlineGroup`: returns `nil` for files AND for
    /// empty directories so neither gets a disclosure chevron. Non-empty
    /// folders return their children, preserving the tree's sort order.
    var outlineChildren: [FileNode]? {
        guard let children, !children.isEmpty else { return nil }
        return children
    }
}
