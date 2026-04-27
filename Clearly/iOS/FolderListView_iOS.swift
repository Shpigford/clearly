import SwiftUI
import ClearlyCore

/// Compact-width (iPhone, iPad split-screen narrow) root. Mac-style outline
/// pattern: a single recursive list with disclosure arrows for folders and
/// tap-to-open rows for files. Pushing onto the navigation stack is reserved
/// for the editor — folder navigation happens via inline expand/collapse.
///
/// Uses a `NavigationPath` so wiki-link / quick-switcher routing through
/// `VaultSession.navigationPath` keeps working unchanged.
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

    @State private var renameTarget: VaultFile?
    @State private var renameDraft: String = ""
    @State private var deleteTarget: VaultFile?

    var body: some View {
        @Bindable var session = session
        NavigationStack(path: $navPath) {
            rootList
                .navigationTitle(rootTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { rootToolbar }
                .refreshable { session.refresh() }
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

    // MARK: - Root list

    private var rootList: some View {
        Group {
            if session.currentVault == nil {
                Color.clear
            } else {
                List {
                    Section {
                        SidebarOutline_iOS(
                            nodes: folderTree,
                            onSelectFile: { file in
                                navPath.append(file)
                                session.markRecent(file)
                            },
                            onRenameFile: { file in beginRename(file) },
                            onDeleteFile: { file in deleteTarget = file },
                            onCreateFile: { folder in createFile(in: folder) },
                            onCreateFolder: { folder in beginCreateFolder(in: folder) }
                        )
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
                createNewNote()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .accessibilityLabel("New note")
            .disabled(session.currentVault == nil)
        }
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

    private func rebuildFolderTree() {
        guard let rootURL = session.currentVault?.url else {
            folderTree = []
            return
        }
        let files = session.files
        Task.detached(priority: .userInitiated) {
            let tree = FileNode.buildTree(at: rootURL, including: files)
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
                _ = try await session.createFolder(named: name, in: parent)
                await MainActor.run {
                    rebuildFolderTree()
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

    private func createNewNote() {
        guard session.currentVault != nil else { return }
        Task {
            do {
                let file = try await session.createUntitledNote(in: nil)
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

    // MARK: - Rename / delete

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

    // MARK: - Welcome

    private var shouldShowWelcomeBinding: Binding<Bool> {
        Binding(
            get: { session.currentVault == nil || showWelcome },
            set: { if !$0 { showWelcome = false } }
        )
    }
}
