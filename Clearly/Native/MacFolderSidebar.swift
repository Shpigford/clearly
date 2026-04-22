import SwiftUI
import ClearlyCore

/// Sidebar selection payload for the native shell. Folder URL or the
/// location-scoped "All Notes" sentinel. Pinned-file rows open directly
/// via `workspace.openFile(at:)` and do not change folder selection.
enum SidebarSelection: Hashable {
    case allNotes(locationID: UUID)
    case folder(URL)

    var folderURL: URL? {
        if case .folder(let url) = self { return url }
        return nil
    }
}

/// Native Apple-Notes-style left sidebar. Lists bookmarked vault locations
/// with an "All Notes" sentinel per location, an `OutlineGroup` of folders
/// beneath, and a Pinned section at the top when non-empty.
struct MacFolderSidebar: View {
    @Bindable var workspace: WorkspaceManager
    @Binding var selection: SidebarSelection?

    @State private var showWelcome = false

    var body: some View {
        List(selection: $selection) {
            if !workspace.pinnedFiles.isEmpty {
                AnyView(pinnedSection)
            }

            ForEach(workspace.locations) { location in
                AnyView(locationSection(location))
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
        .navigationTitle("Clearly")
        .toolbar { sidebarToolbar }
        .sheet(isPresented: $showWelcome) {
            WelcomeSheet(workspace: workspace, isPresented: $showWelcome)
        }
    }

    // MARK: - Pinned section

    private var pinnedSection: some View {
        Section {
            ForEach(workspace.pinnedFiles, id: \.self) { url in
                Button {
                    workspace.openFile(at: url)
                } label: {
                    Label {
                        Text(url.deletingPathExtension().lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(.yellow)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Unpin", systemImage: "pin.slash") {
                        workspace.togglePin(url)
                    }
                    Button("Reveal in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
        } header: {
            Text("Pinned")
        }
    }

    // MARK: - Location section

    private func locationSection(_ location: BookmarkedLocation) -> some View {
        Section {
            Label("All Notes", systemImage: "tray.full")
                .badge(totalFileCount(in: location.fileTree))
                .tag(SidebarSelection.allNotes(locationID: location.id))

            ForEach(topLevelFolders(in: location.fileTree)) { node in
                folderRow(node: node)
            }
        } header: {
            Label(location.name, systemImage: "folder")
        }
    }

    private func folderRow(node: FileNode) -> AnyView {
        let children = node.children ?? []
        let subfolders = children.filter(\.isDirectory)
        if subfolders.isEmpty {
            return AnyView(folderLabel(node))
        }
        return AnyView(
            DisclosureGroup {
                ForEach(subfolders) { child in
                    folderRow(node: child)
                }
            } label: {
                folderLabel(node)
            }
        )
    }

    private func folderLabel(_ node: FileNode) -> some View {
        Label(node.name, systemImage: "folder")
            .badge(fileCount(in: node))
            .tag(SidebarSelection.folder(node.url))
            .contextMenu {
                Button("Reveal in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([node.url])
                }
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
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Add Vault…", systemImage: "folder.badge.plus") {
                    workspace.showOpenPanel()
                }
                Divider()
                Button(workspace.showHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files") {
                    workspace.toggleShowHiddenFiles()
                }
                Divider()
                Button("Open…", systemImage: "doc") {
                    workspace.showOpenPanel()
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: - Derivation

    private func topLevelFolders(in tree: [FileNode]) -> [FileNode] {
        tree.filter(\.isDirectory)
    }

    private func fileCount(in node: FileNode) -> Int {
        guard let children = node.children else { return 0 }
        return children.reduce(0) { count, child in
            count + (child.isDirectory ? fileCount(in: child) : 1)
        }
    }

    private func totalFileCount(in tree: [FileNode]) -> Int {
        tree.reduce(0) { count, node in
            count + (node.isDirectory ? fileCount(in: node) : 1)
        }
    }
}

// MARK: - Welcome sheet

private struct WelcomeSheet: View {
    @Bindable var workspace: WorkspaceManager
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Add a Vault")
                .font(.title)
                .fontWeight(.semibold)
            Text("Pick a folder of markdown files to get started.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                workspace.showOpenPanel()
                isPresented = false
            } label: {
                Text("Choose Folder…")
                    .frame(maxWidth: 200)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(width: 420, height: 320)
    }
}
