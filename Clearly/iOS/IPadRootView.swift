#if os(iOS)
import SwiftUI
import ClearlyCore

/// Regular-width (iPad) root. 2-column `NavigationSplitView`: a Mac-style
/// recursive outline of folders + files in the sidebar, the active note's
/// editor in the detail pane. Selecting a file in the outline opens it via
/// `IPadTabController.openExclusive`.
///
/// Compact-width (iPhone, iPad split-screen narrow) is handled separately
/// by `FolderListView_iOS`. `ContentRoot_iOS` picks the right path off
/// `@Environment(\.horizontalSizeClass)`.
struct IPadRootView: View {
    @Environment(VaultSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    let controller: IPadTabController

    @State private var showWelcome: Bool = false
    @State private var showTags: Bool = false
    @State private var showSettings: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @State private var folderTree: [FileNode] = []

    @State private var renameTarget: VaultFile?
    @State private var renameDraft: String = ""
    @State private var deleteTarget: VaultFile?
    @State private var operationError: String?

    @State private var isCreatingFolder: Bool = false
    @State private var newFolderDraft: String = ""
    @State private var pendingFolderParent: URL?

    var body: some View {
        @Bindable var session = session
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 400)
        } detail: {
            NavigationStack {
                IPadDetailView_iOS(controller: controller)
            }
        }
        .navigationSplitViewStyle(.balanced)
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
                openFile(file)
            })
            .environment(session)
        }
        .sheet(isPresented: $showTags) {
            TagsSheet_iOS(onOpenFile: { file in
                openFile(file)
            })
            .environment(session)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView_iOS()
                .environment(session)
        }
        .background {
            QuickSwitcherShortcuts()
            IPadKeyboardShortcuts(onNewNote: createNewNote)
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
            Text("Name this folder. It will be created inside \(newFolderParentName).")
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
        .onChange(of: session.currentVault?.url) { _, _ in
            controller.bind(to: session)
            rebuildFolderTree()
        }
        .onChange(of: session.files) { _, _ in
            controller.restoreIfNeeded(vault: session)
            controller.reconcileTabURLs()
            rebuildFolderTree()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                flushAllTabs()
            }
        }
        .onAppear {
            controller.bind(to: session)
            rebuildFolderTree()
        }
    }

    // MARK: - Sidebar column

    private var sidebarColumn: some View {
        Group {
            if session.currentVault == nil {
                Color.clear
            } else {
                sidebarList
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { sidebarColumnToolbar }
        .refreshable { session.refresh() }
    }

    private var sidebarList: some View {
        List {
            if let progress = session.indexProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
            }
            Section {
                SidebarOutline_iOS(
                    nodes: folderTree,
                    onSelectFile: { file in openFile(file) },
                    onRenameFile: { file in beginRename(file) },
                    onDeleteFile: { file in deleteTarget = file },
                    onCreateFile: { folder in createFile(in: folder) },
                    onCreateFolder: { folder in beginCreateFolder(in: folder) }
                )
            } header: {
                Text(session.currentVault?.displayName ?? "Vault")
            }
        }
        .listStyle(.sidebar)
    }

    @ToolbarContentBuilder
    private var sidebarColumnToolbar: some ToolbarContent {
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

    // MARK: - Rename / delete

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { newValue in
                if !newValue { renameTarget = nil }
            }
        )
    }

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { newValue in
                if !newValue { deleteTarget = nil }
            }
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
                await MainActor.run {
                    controller.closeTabs(matching: target)
                }
            } catch {
                operationError = error.localizedDescription
            }
        }
    }

    // MARK: - Create folder / file

    private var newFolderParentName: String {
        if let parent = pendingFolderParent {
            return parent.lastPathComponent
        }
        return session.currentVault?.displayName ?? "the vault"
    }

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
                    controller.openExclusive(file)
                }
            } catch {
                operationError = error.localizedDescription
            }
        }
    }

    // MARK: - Other helpers

    private var shouldShowWelcomeBinding: Binding<Bool> {
        Binding(
            get: { session.currentVault == nil || showWelcome },
            set: { newValue in
                if !newValue { showWelcome = false }
            }
        )
    }

    private func flushAllTabs() {
        for tab in controller.tabs {
            Task { await tab.session.flush() }
        }
    }

    private func openFile(_ file: VaultFile) {
        controller.openExclusive(file)
    }

    private func createNewNote() {
        guard session.currentVault != nil else { return }
        Task {
            do {
                let file = try await session.createUntitledNote(in: nil)
                await MainActor.run {
                    controller.openExclusive(file)
                    rebuildFolderTree()
                }
            } catch {
                DiagnosticLog.log("[iPad] createUntitledNote failed: \(error.localizedDescription)")
            }
        }
    }
}

/// Hidden-button hardware-keyboard shortcuts. ⌘N = new note. ⌘K (quick
/// switcher) is registered separately via `QuickSwitcherShortcuts`.
struct IPadKeyboardShortcuts: View {
    @Environment(VaultSession.self) private var session
    let onNewNote: () -> Void

    var body: some View {
        ZStack {
            Color.clear
            Button(action: onNewNote) {
                Label("New Note", systemImage: "square.and.pencil")
            }
            .keyboardShortcut("n", modifiers: .command)
            .hidden()
        }
        .accessibilityHidden(true)
        .disabled(session.currentVault == nil)
    }
}
#endif
