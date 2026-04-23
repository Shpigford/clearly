import SwiftUI
import ClearlyCore

/// Compact-width (iPhone, iPad split-screen narrow) root. Notes-app drill-in
/// navigation: folders on screen 1, files in the selected folder on screen 2,
/// editor on screen 3. Mirrors the iPad 3-column layout but compressed into
/// a NavigationStack because there's only one column of real estate.
///
/// Uses a `NavigationPath` so the stack can hold both URL-typed folder
/// destinations and VaultFile-typed editor destinations heterogeneously.
struct FolderListView_iOS: View {
    @Environment(VaultSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    @State private var navPath = NavigationPath()
    @State private var folderTree: [FileNode] = []
    @State private var showWelcome: Bool = false
    @State private var showTags: Bool = false
    @State private var showSettings: Bool = false

    @State private var isCreatingFolder: Bool = false
    @State private var newFolderDraft: String = ""
    @State private var pendingFolderParent: URL?
    @State private var operationError: String?

    /// Matches `IPadRootView.allNotesSentinel` so the two layouts route folder
    /// selection the same way. Keeping one sentinel URL across the app means
    /// the selection vocabulary is consistent everywhere we might eventually
    /// persist it.
    static let allNotesSentinel = IPadRootView.allNotesSentinel

    var body: some View {
        @Bindable var session = session
        NavigationStack(path: $navPath) {
            rootList
                .navigationTitle(rootTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { rootToolbar }
                .refreshable { session.refresh() }
                .navigationDestination(for: URL.self) { folderURL in
                    FileListView_iOS(folderURL: folderURL, allNotesSentinel: Self.allNotesSentinel)
                }
                .navigationDestination(for: VaultFile.self) { file in
                    RawTextDetailView_iOS(file: file)
                }
        }
        .fullScreenCover(isPresented: shouldShowWelcomeBinding) {
            WelcomeView_iOS()
                .interactiveDismissDisabled(session.currentVault == nil)
                .onChange(of: session.currentVault?.id) { _, _ in
                    if session.currentVault != nil {
                        showWelcome = false
                    }
                }
        }
        .sheet(isPresented: $session.isShowingQuickSwitcher) {
            QuickSwitcherSheet_iOS(onOpenFile: { file in
                navPath = NavigationPath()
                navPath.append(file)
                session.markRecent(file)
            })
            .environment(session)
        }
        .sheet(isPresented: $showTags) {
            TagsSheet_iOS(onOpenFile: { file in
                navPath.append(file)
            })
            .environment(session)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView_iOS()
                .environment(session)
        }
        .alert("New Folder", isPresented: $isCreatingFolder) {
            TextField("Name", text: $newFolderDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {
                newFolderDraft = ""
                pendingFolderParent = nil
            }
            Button("Create") { commitCreateFolder() }
        } message: {
            Text("Name this folder. It will be created in \(newFolderLocationDescription).")
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
        .onChange(of: session.currentVault?.url) { _, _ in rebuildFolderTree() }
        .onChange(of: session.files) { _, _ in rebuildFolderTree() }
        .onChange(of: session.navigationPath) { _, newValue in
            // Legacy file-navigation bridge: wiki-link / external openers
            // still append to `session.navigationPath`; hop that into the
            // local NavigationPath so those flows keep working.
            guard let last = newValue.last else { return }
            if navPath.count > 0 {
                navPath = NavigationPath()
            }
            navPath.append(last)
            session.navigationPath = []
        }
        .onAppear { rebuildFolderTree() }
    }

    // MARK: - Root folder list

    private var rootList: some View {
        Group {
            if session.currentVault == nil {
                Color.clear
            } else {
                List {
                    Section {
                        NavigationLink(value: Self.allNotesSentinel) {
                            Label("All Notes", systemImage: "tray.full")
                                .badge(session.files.count)
                        }
                        OutlineGroup(topLevelFolders, children: \.directoryChildren) { node in
                            NavigationLink(value: node.url) {
                                Label(node.name, systemImage: "folder")
                                    .badge(fileCount(in: node.url))
                            }
                            .contextMenu {
                                Button {
                                    createFile(in: node.url)
                                } label: {
                                    Label("New File", systemImage: "doc.badge.plus")
                                }
                                Button {
                                    beginCreateFolder(in: node.url)
                                } label: {
                                    Label("New Folder", systemImage: "folder.badge.plus")
                                }
                            }
                        }
                    } header: {
                        Text(session.currentVault?.displayName ?? "Vault")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private var rootTitle: String {
        session.currentVault?.displayName ?? "Clearly"
    }

    @ToolbarContentBuilder
    private var rootToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                beginCreateFolder()
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .accessibilityLabel("New folder")
            .disabled(session.currentVault == nil)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                session.isShowingQuickSwitcher = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Search notes")
            .disabled(session.currentVault == nil)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    showTags = true
                } label: {
                    Label("Tags", systemImage: "tag")
                }
                .disabled(session.currentVault == nil)
                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                Button {
                    showWelcome = true
                } label: {
                    Label("Change Vault", systemImage: "folder")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }
    }

    // MARK: - Folder tree

    private var topLevelFolders: [FileNode] {
        folderTree.filter { $0.isDirectory }
    }

    private func fileCount(in folderURL: URL) -> Int {
        let target = folderURL.standardizedFileURL
        return session.files.reduce(into: 0) { acc, file in
            if file.url.deletingLastPathComponent().standardizedFileURL == target {
                acc += 1
            }
        }
    }

    private func rebuildFolderTree() {
        guard let rootURL = session.currentVault?.url else {
            folderTree = []
            return
        }
        Task.detached(priority: .userInitiated) {
            let tree = FileNode.buildTree(at: rootURL)
            await MainActor.run {
                folderTree = tree
            }
        }
    }

    // MARK: - Create folder / file

    private func beginCreateFolder(in parent: URL? = nil) {
        newFolderDraft = ""
        pendingFolderParent = parent
        isCreatingFolder = true
    }

    private func commitCreateFolder() {
        let name = newFolderDraft
        let parent = pendingFolderParent
        newFolderDraft = ""
        pendingFolderParent = nil
        Task {
            do {
                let url = try await session.createFolder(named: name, in: parent)
                await MainActor.run {
                    rebuildFolderTree()
                    navPath.append(url)
                }
            } catch VaultSessionError.readFailed(let msg) {
                operationError = msg
            } catch {
                operationError = error.localizedDescription
            }
        }
    }

    private func createFile(in folder: URL) {
        Task {
            do {
                let file = try await session.createUntitledNote(in: folder)
                await MainActor.run {
                    rebuildFolderTree()
                    navPath.append(file)
                    session.markRecent(file)
                }
            } catch {
                operationError = error.localizedDescription
            }
        }
    }

    private var newFolderLocationDescription: String {
        if let parent = pendingFolderParent {
            return parent.lastPathComponent
        }
        return session.currentVault?.displayName ?? "the vault"
    }

    // MARK: - Welcome

    private var shouldShowWelcomeBinding: Binding<Bool> {
        Binding(
            get: { session.currentVault == nil || showWelcome },
            set: { if !$0 { showWelcome = false } }
        )
    }
}
