#if os(iOS)
import SwiftUI
import ClearlyCore

/// Regular-width (iPad) root. Stock 3-column `NavigationSplitView`:
/// folders on the left, notes in the selected folder in the middle, the
/// active note's editor on the right. Mirrors Apple Notes's iPad layout.
/// Vault-as-folder-tree uses `FileNode.buildTree` (rebuilt off-main when
/// the watcher's flat file list changes); the file list is derived from
/// `vault.files` by filtering to direct children of the selected folder.
///
/// Compact-width (iPhone, iPad split-screen narrow) is handled separately
/// by `SidebarView_iOS`. `ContentRoot_iOS` picks the right path off
/// `@Environment(\.horizontalSizeClass)`.
struct IPadRootView: View {
    @Environment(VaultSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    let controller: IPadTabController

    @State private var showWelcome: Bool = false
    @State private var showTags: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @State private var folderTree: [FileNode] = []
    @State private var selectedFolderURL: URL? = Self.allNotesSentinel
    @State private var selectedFileURL: URL?

    /// Sentinel URL representing the "All Notes" pseudo-folder. Lets the
    /// selection binding stay `URL?`, which matches `OutlineGroup`'s natural
    /// `FileNode.id` (also `URL`) — homogeneous selection types are what
    /// `List(selection:)` needs to route taps to the right binding update.
    static let allNotesSentinel = URL(string: "clearly://all-notes")!

    @State private var renameTarget: VaultFile?
    @State private var renameDraft: String = ""
    @State private var deleteTarget: VaultFile?
    @State private var operationError: String?

    @State private var isCreatingFolder: Bool = false
    @State private var newFolderDraft: String = ""

    var body: some View {
        @Bindable var session = session
        NavigationSplitView(columnVisibility: $columnVisibility) {
            folderColumn
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } content: {
            fileColumn
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
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
            Button("Cancel", role: .cancel) { newFolderDraft = "" }
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
            syncSelectionFromController()
            rebuildFolderTree()
        }
        .onChange(of: controller.activeTabID) { _, _ in
            syncSelectionFromController()
        }
        .onChange(of: selectedFileURL) { _, newURL in
            handleSelectionChange(newURL)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                flushAllTabs()
            }
        }
        .onAppear {
            controller.bind(to: session)
            syncSelectionFromController()
            rebuildFolderTree()
        }
    }

    // MARK: - Folder column (left)

    private var folderColumn: some View {
        Group {
            if session.currentVault == nil {
                Color.clear
            } else {
                folderList
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { folderColumnToolbar }
    }

    private var folderList: some View {
        List(selection: $selectedFolderURL) {
            Section {
                Label("All Notes", systemImage: "tray.full")
                    .badge(session.files.count)
                    .tag(Self.allNotesSentinel)
                OutlineGroup(topLevelFolders, children: \.directoryChildren) { node in
                    Label(node.name, systemImage: "folder")
                        .badge(fileCount(in: node.url))
                        .tag(node.url)
                }
            } header: {
                Text(vaultSectionTitle)
            }
        }
        .listStyle(.sidebar)
    }

    /// Section header for the leftmost column — the vault's display name,
    /// matching Notes.app's "iCloud" / account-name grouping.
    private var vaultSectionTitle: String {
        session.currentVault?.displayName ?? "Vault"
    }

    @ToolbarContentBuilder
    private var folderColumnToolbar: some ToolbarContent {
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
            Menu {
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

    // MARK: - File column (middle)

    private var fileColumn: some View {
        Group {
            if session.currentVault == nil {
                Color.clear
            } else if session.files.isEmpty && session.isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if displayedFiles.isEmpty {
                emptyFolderState
            } else {
                fileList
            }
        }
        .navigationTitle(folderColumnTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { fileColumnToolbar }
        .refreshable { session.refresh() }
    }

    private var fileList: some View {
        List(selection: $selectedFileURL) {
            if let progress = session.indexProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
            }
            ForEach(displayedFiles) { file in
                FileListRowContent(file: file, liveText: liveText(for: file))
                    .tag(file.url)
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
        .listStyle(.sidebar)
    }

    private var emptyFolderState: some View {
        ContentUnavailableView(
            displayedFiles.isEmpty && session.files.isEmpty ? "No notes yet" : "No notes in this folder",
            systemImage: "tray",
            description: Text("Tap + to create your first note here.")
        )
    }

    @ToolbarContentBuilder
    private var fileColumnToolbar: some ToolbarContent {
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
                session.isShowingQuickSwitcher = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Search notes")
            .disabled(session.currentVault == nil)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showTags = true
            } label: {
                Image(systemName: "tag")
            }
            .accessibilityLabel("Browse tags")
            .disabled(session.currentVault == nil)
        }
    }

    // MARK: - Folder + file derivation

    private var topLevelFolders: [FileNode] {
        folderTree.filter { $0.isDirectory }
    }

    private var folderColumnTitle: String {
        if isAllNotesSelected {
            return session.currentVault?.displayName ?? "Notes"
        }
        return selectedFolderURL?.lastPathComponent ?? "Notes"
    }

    /// Files visible in the middle column. "All Notes" shows everything;
    /// a folder shows only its direct children. Always sorted by modified
    /// date descending so recently-touched notes float to the top.
    private var displayedFiles: [VaultFile] {
        let sorted = session.files.sorted { lhs, rhs in
            (lhs.modified ?? .distantPast) > (rhs.modified ?? .distantPast)
        }
        if isAllNotesSelected {
            return sorted
        }
        guard let target = selectedFolderURL?.standardizedFileURL else { return sorted }
        return sorted.filter { $0.url.deletingLastPathComponent().standardizedFileURL == target }
    }

    private var isAllNotesSelected: Bool {
        selectedFolderURL == nil || selectedFolderURL == Self.allNotesSentinel
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

    /// Returns the active document's in-memory text if `file` is the currently
    /// open document, otherwise nil.
    private func liveText(for file: VaultFile) -> String? {
        guard let tab = controller.activeTab else { return nil }
        let activeURL = (tab.session.file?.url ?? tab.file.url).standardizedFileURL
        guard activeURL == file.url.standardizedFileURL else { return nil }
        return tab.session.text
    }

    // MARK: - Selection ↔ controller sync

    private func syncSelectionFromController() {
        let activeURL = controller.activeTab.flatMap { tab in
            (tab.session.file?.url ?? tab.file.url).standardizedFileURL
        }
        if selectedFileURL != activeURL {
            selectedFileURL = activeURL
        }
    }

    private func handleSelectionChange(_ newURL: URL?) {
        guard let newURL else { return }
        let activeURL = controller.activeTab.flatMap { tab in
            (tab.session.file?.url ?? tab.file.url).standardizedFileURL
        }
        if newURL == activeURL { return }
        if let file = session.files.first(where: { $0.url.standardizedFileURL == newURL }) {
            controller.openExclusive(file)
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

    // MARK: - Create folder

    /// Where the new folder should be created. Same precedence as new-note
    /// placement: a selected folder becomes the parent, "All Notes" means
    /// the vault root.
    private var newFolderParent: URL? {
        isAllNotesSelected ? nil : selectedFolderURL
    }

    private var newFolderParentName: String {
        if isAllNotesSelected {
            return session.currentVault?.displayName ?? "the vault"
        }
        return selectedFolderURL?.lastPathComponent ?? "the vault"
    }

    private func beginCreateFolder() {
        newFolderDraft = ""
        isCreatingFolder = true
    }

    private func commitCreateFolder() {
        let name = newFolderDraft
        newFolderDraft = ""
        let parent = newFolderParent
        Task {
            do {
                let url = try await session.createFolder(named: name, in: parent)
                await MainActor.run {
                    rebuildFolderTree()
                    selectedFolderURL = url
                }
            } catch VaultSessionError.readFailed(let msg) {
                operationError = msg
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

    /// Where new notes land. "All Notes" → vault root. A specific folder →
    /// that folder. So a user browsing PROJECTS hits + and the new note
    /// lands inside PROJECTS, matching Notes.app's behavior.
    private var newNoteParent: URL? {
        isAllNotesSelected ? nil : selectedFolderURL
    }

    private func createNewNote() {
        guard session.currentVault != nil else { return }
        let parent = newNoteParent
        Task {
            do {
                let file = try await session.createUntitledNote(in: parent)
                await MainActor.run {
                    controller.openExclusive(file)
                }
            } catch {
                DiagnosticLog.log("[iPad] createUntitledNote failed: \(error.localizedDescription)")
            }
        }
    }
}

extension FileNode {
    /// Directory children only — used by `OutlineGroup` so the folder column
    /// shows folders-in-folders but never files (those live in the middle
    /// column). Returns nil when there are no directory children so the
    /// outline disclosure indicator hides for leaf folders.
    var directoryChildren: [FileNode]? {
        let dirs = (children ?? []).filter { $0.isDirectory }
        return dirs.isEmpty ? nil : dirs
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
