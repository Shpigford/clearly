import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ClearlyCore

// MARK: - Toolbar (root-attached)

/// Detail-column toolbar, attached by `MacRootView` to the outermost
/// NavigationSplitView. Attaching it to the detail column itself wedges the
/// items against the middle-column divider on macOS 26 — attaching here
/// lets them occupy the window's trailing toolbar slot, which is what
/// Apple Notes does.
struct MacDetailToolbar: ToolbarContent {
    @Bindable var workspace: WorkspaceManager
    @ObservedObject var findState: FindState
    @ObservedObject var outlineState: OutlineState
    @ObservedObject var backlinksState: BacklinksState
    @Bindable var wikiController: WikiOperationController
    @Binding var showFormatPopover: Bool
    @AppStorage("editorEngine") private var editorEngineRawValue = EditorEngine.classic.rawValue

    private var editorEngine: EditorEngine {
        EditorEngine.resolved(rawValue: editorEngineRawValue)
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if editorEngine == .livePreviewExperimental {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles.rectangle.stack")
                    Text("Live Preview")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .fixedSize()
                .help("Live Preview")
            } else {
                Picker("Mode", selection: $workspace.currentViewMode) {
                    Image(systemName: "pencil").tag(ViewMode.edit)
                    Image(systemName: "eye").tag(ViewMode.preview)
                }
                .pickerStyle(.segmented)
                .help("Editor / Preview (⌘1 / ⌘2)")
            }
        }

        // Trailing: everything else, clustered on the far right.
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                workspace.createUntitledDocument()
            } label: {
                Label("New Note", systemImage: "square.and.pencil")
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("New Note (⌘N)")

            Button {
                showFormatPopover.toggle()
            } label: {
                Label("Format", systemImage: "textformat")
            }
            .help("Format")
            .disabled(workspace.activeDocumentID == nil || workspace.currentViewMode != .edit)
            .popover(isPresented: $showFormatPopover, arrowEdge: .bottom) {
                MacFormatPopover()
            }

            Button {
                performFormattingCommand(.todoList, selector: #selector(ClearlyTextView.toggleTodoList(_:)))
            } label: {
                Label("Checklist", systemImage: "checklist")
            }
            .help("Insert checklist item")
            .disabled(workspace.activeDocumentID == nil || workspace.currentViewMode != .edit)

            Menu {
                Button("Insert Link…") {
                    performFormattingCommand(.link, selector: #selector(ClearlyTextView.insertLink(_:)))
                }
                Button("Insert Image…") {
                    performFormattingCommand(.image, selector: #selector(ClearlyTextView.insertImage(_:)))
                }
                Button("Insert Table") {
                    performFormattingCommand(.table, selector: #selector(ClearlyTextView.insertMarkdownTable(_:)))
                }
                Button("Insert Code Block") {
                    performFormattingCommand(.codeBlock, selector: #selector(ClearlyTextView.insertCodeBlock(_:)))
                }
            } label: {
                Label("Insert", systemImage: "paperclip")
            }
            .help("Insert link, image, table, or code")
            .menuIndicator(.hidden)
            .disabled(workspace.activeDocumentID == nil || workspace.currentViewMode != .edit)

            Menu {
                if let url = workspace.currentFileURL {
                    Button("Copy File Path") { CopyActions.copyFilePath(url) }
                    Button("Copy File Name") { CopyActions.copyFileName(url) }
                    if let root = workspace.containingVaultRoot(for: url) {
                        Button("Copy Relative Path") { CopyActions.copyRelativePath(url, vaultRoot: root) }
                    }
                    if let target = workspace.wikiLinkTarget(for: url) {
                        Button("Copy Wiki Link") { CopyActions.copyWikiLink(target) }
                    }
                    Divider()
                }
                Button("Copy Markdown") { CopyActions.copyMarkdown(workspace.currentFileText) }
                Button("Copy HTML") { CopyActions.copyHTML(workspace.currentFileText) }
                Button("Copy Rich Text") { CopyActions.copyRichText(workspace.currentFileText) }
                Button("Copy Plain Text") { CopyActions.copyPlainText(workspace.currentFileText) }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .help("Copy document content")
            .menuIndicator(.hidden)
            .disabled(workspace.activeDocumentID == nil)

            Button {
                withAnimation(Theme.Motion.smooth) { backlinksState.toggle() }
            } label: {
                Label("Backlinks", systemImage: "link")
            }
            .help("Backlinks (⇧⌘B)")
            .disabled(workspace.activeDocumentID == nil)

            Button {
                outlineState.toggle()
            } label: {
                Label("Outline", systemImage: "list.bullet.indent")
            }
            .help("Outline (⇧⌘O)")
            .disabled(workspace.activeDocumentID == nil)

            Button {
                findState.toggle()
            } label: {
                Label("Find", systemImage: "magnifyingglass")
            }
            .help("Find in note (⌘F)")
            .disabled(workspace.activeDocumentID == nil)

            if let url = workspace.currentFileURL {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .help("Share")
            }
        }

        // Visual break so the wiki actions render as their own Liquid Glass
        // pill on macOS 26+, mirroring the centered editor/preview group.
        if workspace.activeVaultIsWiki {
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                // Auto-Review surfaced affordance. Only renders when the agent
                // has parked a proposal on `pendingOperation`; click goes
                // straight to the diff sheet (skipping the sidebar). Lives in
                // the wiki cluster so it sits next to Capture/Chat — the
                // LogSidebar header badge alone is invisible to anyone who
                // keeps the sidebar closed.
                if wikiController.hasPendingReview {
                    let count = wikiController.pendingOperation?.changes.count ?? 0
                    Button {
                        wikiController.presentPending()
                    } label: {
                        Image(systemName: "sparkles")
                            .overlay(alignment: .topTrailing) {
                                Text("\(count)")
                                    .font(.system(size: 9, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.accentColor))
                                    .offset(x: 8, y: -6)
                            }
                    }
                    .help("Review ready · \(count) change\(count == 1 ? "" : "s")")
                }

                Button {
                    NotificationCenter.default.post(name: .wikiCapture, object: nil)
                } label: {
                    Label("Capture", systemImage: "tray.and.arrow.down")
                }
                .help("Capture into this wiki (⌃⌘I)")

                Button {
                    NotificationCenter.default.post(name: .wikiChat, object: nil)
                } label: {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right")
                }
                .help("Chat with this wiki (⌃⌘A)")
            }
        }
    }
}

/// Detail column for the native shell — editor/preview ZStack with opacity
/// crossfade, conflict banner + find/jump overlays at the top, and the
/// outline panel mounted as an HStack sibling on the trailing edge.
struct MacDetailColumn: View {
    private struct PendingWikiNavigation {
        let fileURL: URL
        let lineNumber: Int
        let destinationMode: ViewMode
    }

    @Bindable var workspace: WorkspaceManager
    @ObservedObject var findState: FindState
    @ObservedObject var outlineState: OutlineState
    @ObservedObject var backlinksState: BacklinksState
    @ObservedObject var jumpToLineState: JumpToLineState
    @Bindable var wikiController: WikiOperationController
    @Bindable var wikiChat: WikiChatState
    @Bindable var wikiLog: WikiLogState
    @Bindable var wikiCapture: WikiCaptureState
    @Binding var positionSyncID: String
    @Binding var showFormatPopover: Bool

    @StateObject private var fileWatcher = FileWatcher()
    @State private var isFullscreen = false
    @State private var pendingWikiNavigation: PendingWikiNavigation?

    @AppStorage("editorFontSize") private var fontSize: Double = 16
    @AppStorage("previewFontFamily") private var previewFontFamily: String = "sanFrancisco"
    @AppStorage("editorEngine") private var editorEngineRawValue = EditorEngine.classic.rawValue
    @AppStorage("contentWidth") private var contentWidth: String = "default"
    @AppStorage("showLineNumbers") private var showLineNumbers: Bool = false

    private var editorEngine: EditorEngine {
        EditorEngine.resolved(rawValue: editorEngineRawValue)
    }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if workspace.activeDocumentID == nil {
                    emptyState
                } else {
                    editorPreviewStack
                }
            }
            .frame(maxWidth: .infinity)

            if outlineState.isVisible {
                OutlineView(outlineState: outlineState)
                    .frame(width: 240)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if wikiChat.isVisible {
                WikiChatView(
                    chat: wikiChat,
                    controller: wikiController,
                    vaultRoot: workspace.activeLocation?.url,
                    send: { text in
                        WikiAgentCoordinator.sendChatMessage(text, workspace: workspace, chat: wikiChat)
                    },
                    openWikiLink: { target in
                        if let url = resolveWikiLink(target) {
                            workspace.openFile(at: url)
                        }
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if wikiLog.isVisible {
                Divider()
                WikiLogSidebar(
                    state: wikiLog,
                    controller: wikiController,
                    vaultRoot: workspace.activeLocation?.url,
                    openPath: { relativePath in
                        guard let vaultURL = workspace.activeLocation?.url else { return }
                        let fileURL = vaultURL.appendingPathComponent(relativePath)
                        if FileManager.default.fileExists(atPath: fileURL.path) {
                            workspace.openFile(at: fileURL)
                        }
                    },
                    openLog: {
                        guard let vaultURL = workspace.activeLocation?.url else { return }
                        workspace.openFile(at: vaultURL.appendingPathComponent(WikiLogWriter.filename))
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.smooth, value: outlineState.isVisible)
        .animation(Theme.Motion.smooth, value: wikiChat.isVisible)
        .animation(Theme.Motion.smooth, value: wikiLog.isVisible)
        .navigationTitle(documentTitle)
        .onAppear(perform: handleAppear)
        .onChange(of: workspace.activeLocation?.id) { _, _ in
            handleActiveVaultChanged()
        }
        .onChange(of: workspace.treeRevision) { _, _ in
            handleTreeRevisionChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullscreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullscreen = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ClearlyToggleOutline"))) { _ in
            withAnimation(Theme.Motion.smooth) {
                outlineState.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ClearlyToggleBacklinks"))) { _ in
            withAnimation(Theme.Motion.smooth) {
                backlinksState.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ClearlyToggleLineNumbers"))) { _ in
            showLineNumbers.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ClearlyJumpToLine"))) { _ in
            guard workspace.currentViewMode == .edit else { return }
            withAnimation(Theme.Motion.smooth) {
                jumpToLineState.toggle()
            }
        }
        .onChange(of: workspace.activeDocumentID) { _, _ in
            positionSyncID = UUID().uuidString
            findState.dismiss()
            jumpToLineState.dismiss()
            if editorEngine == .livePreviewExperimental {
                workspace.currentViewMode = .edit
            }
            outlineState.parseHeadings(from: workspace.currentFileText)
            backlinksState.update(for: workspace.currentFileURL, using: workspace.activeVaultIndexes)
            setupFileWatcher()
            applyPendingWikiNavigationIfNeeded()
        }
        .onChange(of: workspace.currentViewMode) { oldMode, newMode in
            if editorEngine == .livePreviewExperimental, newMode != .edit {
                workspace.currentViewMode = .edit
                return
            }
            if newMode != .edit {
                jumpToLineState.dismiss()
            }
            guard oldMode != newMode,
                  let text = SelectionBridge.selection(for: positionSyncID) else { return }
            if oldMode == .edit && newMode == .preview {
                NotificationCenter.default.post(name: .highlightTextInPreview, object: nil, userInfo: ["text": text])
            } else if oldMode == .preview && newMode == .edit {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NotificationCenter.default.post(name: .highlightTextInEditor, object: nil, userInfo: ["text": text])
                }
            }
        }
        .onChange(of: workspace.currentFileText) { _, text in
            if editorEngine == .livePreviewExperimental {
                workspace.contentDidChange()
            }
            fileWatcher.updateCurrentText(text)
            outlineState.parseHeadings(from: text)
        }
        .onChange(of: workspace.currentFileURL) { _, _ in
            setupFileWatcher()
        }
        .onChange(of: workspace.vaultIndexRevision) { _, _ in
            backlinksState.update(for: workspace.currentFileURL, using: workspace.activeVaultIndexes)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateWikiLink)) { notification in
            guard let target = notification.userInfo?["target"] as? String else { return }
            let heading = notification.userInfo?["heading"] as? String
            navigateToWikiLink(target: target, heading: heading, destinationMode: .edit)
        }
        .onChange(of: editorEngineRawValue) { _, _ in
            if editorEngineRawValue != editorEngine.rawValue {
                editorEngineRawValue = editorEngine.rawValue
            }
            if editorEngine == .livePreviewExperimental {
                workspace.currentViewMode = .edit
            }
        }
        .modifier(FocusedValuesModifier(
            workspace: workspace,
            findState: findState,
            outlineState: outlineState,
            backlinksState: backlinksState,
            jumpToLineState: jumpToLineState
        ))
        .modifier(WikiSheetsModifier(
            workspace: workspace,
            wikiController: wikiController,
            wikiCapture: wikiCapture,
            onOperationApplied: handleOperationApplied
        ))
        .overlay(alignment: .bottom) {
            WikiRecipeProgressOverlay(controller: wikiController)
                .animation(Theme.Motion.smooth, value: wikiController.isRunningRecipe)
        }
        .modifier(WikiNotificationObserversModifier(
            workspace: workspace,
            wikiController: wikiController,
            wikiChat: wikiChat,
            wikiLog: wikiLog,
            wikiCapture: wikiCapture
        ))
    }

    private func handleOperationApplied(_ operation: WikiOperation, vaultURL: URL) {
        DiagnosticLog.log("Applied WikiOperation: \(operation.kind.rawValue) — \(operation.title), \(operation.changes.count) changes")
        // Append to log.md so the vault's own history tracks this operation.
        // Not part of the atomic apply — a log-write failure is surfaced but
        // doesn't roll back the already-committed changes.
        do {
            try WikiLogWriter.appendOperation(operation, to: vaultURL)
        } catch {
            DiagnosticLog.log("WikiLogWriter: append failed — \(error)")
        }
        if wikiLog.isVisible {
            wikiLog.reload(vaultRoot: vaultURL)
        }
    }

    private func handleAppear() {
        if editorEngineRawValue != editorEngine.rawValue {
            editorEngineRawValue = editorEngine.rawValue
        }
        if editorEngine == .livePreviewExperimental {
            workspace.currentViewMode = .edit
        }
        outlineState.parseHeadings(from: workspace.currentFileText)
        backlinksState.update(for: workspace.currentFileURL, using: workspace.activeVaultIndexes)
        isFullscreen = NSApp.mainWindow?.styleMask.contains(.fullScreen) ?? false
        setupFileWatcher()
        warmAndReviewActiveVaultIfNeeded()
    }

    private func handleTreeRevisionChanged() {
        if wikiLog.isVisible, workspace.activeVaultIsWiki {
            wikiLog.reload(vaultRoot: workspace.activeLocation?.url)
        }
        warmAndReviewActiveVaultIfNeeded()
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView(
            "No Document Open",
            systemImage: "doc.text",
            description: Text("Pick a note from the sidebar or press ⌘N for a new one.")
        )
    }

    // MARK: - Editor / preview stack

    private var editorPreviewStack: some View {
        VStack(spacing: 0) {
            if let outcome = workspace.currentConflictOutcome {
                ConflictBannerView(outcome: outcome) {
                    NSWorkspace.shared.activateFileViewerSelecting([outcome.siblingURL])
                }
            }

            if findState.isVisible {
                FindBarView(findState: findState)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }

            if jumpToLineState.isVisible {
                JumpToLineBar(state: jumpToLineState)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }

            ZStack {
                if editorEngine == .classic {
                    editorPane
                        .opacity(workspace.currentViewMode == .edit ? 1 : 0)
                        .allowsHitTesting(workspace.currentViewMode == .edit)
                    previewPane
                        .opacity(workspace.currentViewMode == .preview ? 1 : 0)
                        .allowsHitTesting(workspace.currentViewMode == .preview)
                } else {
                    liveEditorPane
                    if workspace.currentFileText.isEmpty {
                        LivePreviewEmptyState()
                            .allowsHitTesting(false)
                            .padding(.horizontal, 48)
                    }
                }
            }
            .layoutPriority(1)

            if backlinksState.isVisible {
                Divider()
                BacklinksView(backlinksState: backlinksState) { backlink in
                    let fileURL = backlink.vaultRootURL.appendingPathComponent(backlink.sourcePath)
                    if workspace.openFile(at: fileURL) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            NotificationCenter.default.post(
                                name: .scrollEditorToLine, object: nil,
                                userInfo: ["line": backlink.lineNumber]
                            )
                        }
                    }
                } onLink: { _ in /* no-op for now */ }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: 200)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.smooth, value: workspace.currentViewMode)
        .animation(Theme.Motion.smooth, value: findState.isVisible)
        .animation(Theme.Motion.smooth, value: jumpToLineState.isVisible)
        .animation(Theme.Motion.smooth, value: backlinksState.isVisible)
    }

    private var editorPane: some View {
        EditorView(
            text: $workspace.currentFileText,
            fontSize: CGFloat(fontSize),
            fileURL: workspace.currentFileURL,
            mode: workspace.currentViewMode,
            positionSyncID: positionSyncID,
            findState: findState,
            outlineState: outlineState,
            extraTopInset: 0,
            showLineNumbers: showLineNumbers,
            jumpToLineState: jumpToLineState,
            needsTrafficLightClearance: false,
            contentWidthEm: contentWidthEm
        )
    }

    private var liveEditorPane: some View {
        LiveEditorView(
            text: $workspace.currentFileText,
            fontSize: CGFloat(fontSize),
            fileURL: workspace.currentFileURL,
            documentID: workspace.activeDocumentID,
            documentEpoch: workspace.documentEpoch,
            findState: findState,
            outlineState: outlineState,
            onMarkdownLinkClicked: { href in
                openMarkdownLink(href)
            },
            onWikiLinkClicked: { target, heading in
                navigateToWikiLink(target: target, heading: heading, destinationMode: .edit)
            },
            onTagClicked: { tagName in
                NotificationCenter.default.post(
                    name: .init("ClearlyFilterByTag"),
                    object: nil,
                    userInfo: ["tag": tagName]
                )
            },
            onFlushContent: { [workspace] text in
                guard text != workspace.currentFileText else { return }
                workspace.currentFileText = text
            }
        )
    }

    private var previewPane: some View {
        let fileURL = workspace.currentFileURL
        _ = workspace.vaultIndexRevision
        let allWikiFileNames: Set<String> = {
            var names = Set<String>()
            for index in workspace.activeVaultIndexes {
                for file in index.allFiles() {
                    names.insert(file.filename.lowercased())
                    names.insert(file.path.lowercased())
                    names.insert((file.path as NSString).deletingPathExtension.lowercased())
                }
            }
            return names
        }()
        return PreviewView(
            markdown: workspace.currentFileText,
            fontSize: CGFloat(fontSize),
            fontFamily: previewFontFamily,
            mode: workspace.currentViewMode,
            positionSyncID: positionSyncID,
            fileURL: fileURL,
            findState: findState,
            outlineState: outlineState,
            onTaskToggle: { [workspace] line, checked in
                toggleTask(at: line, checked: checked, workspace: workspace)
            },
            onWikiLinkClicked: { target, heading in
                navigateToWikiLink(target: target, heading: heading, destinationMode: .preview)
            },
            onTagClicked: { tag in
                NotificationCenter.default.post(
                    name: .init("ClearlyFilterByTag"), object: nil, userInfo: ["tag": tag]
                )
            },
            wikiFileNames: allWikiFileNames,
            contentWidthEm: contentWidthEm,
            extraTopInset: 0
        )
    }


    // MARK: - Derivation

    private var documentTitle: String {
        guard let docID = workspace.activeDocumentID,
              let doc = workspace.openDocuments.first(where: { $0.id == docID }) else {
            return "Clearly"
        }
        let base = doc.displayName
        return workspace.isDirty ? "\u{2022} \(base)" : base
    }

    private var contentWidthEm: CGFloat? {
        switch contentWidth {
        case "narrow": return 36
        case "medium": return 48
        case "wide":   return 60
        default:       return nil
        }
    }

    // MARK: - Helpers

    private func handleActiveVaultChanged() {
        let vaultURL = workspace.activeVaultIsWiki ? workspace.activeLocation?.url : nil
        wikiController.clearPendingReviewIfVaultChanged(to: vaultURL)
        wikiChat.reset(vaultRoot: vaultURL)
        wikiLog.reload(vaultRoot: vaultURL)

        if vaultURL == nil {
            wikiChat.hide()
            wikiLog.hide()
        }

        warmAndReviewActiveVaultIfNeeded()
    }

    private func warmAndReviewActiveVaultIfNeeded() {
        WikiAgentCoordinator.warmForActiveVaultIfPossible(workspace: workspace)
        WikiAgentCoordinator.runReviewIfStale(workspace: workspace, controller: wikiController)
    }

    private func setupFileWatcher() {
        fileWatcher.liveCurrentText = { [workspace] in
            workspace.liveCurrentFileText()
        }
        guard let url = workspace.currentFileURL else {
            fileWatcher.watch(nil, currentText: nil)
            return
        }
        fileWatcher.onChange = { [workspace] newText in
            workspace.externalFileDidChange(newText)
        }
        fileWatcher.watch(url, currentText: workspace.currentFileText)
    }

    private func toggleTask(at line: Int, checked: Bool, workspace: WorkspaceManager) {
        var lines = workspace.currentFileText.components(separatedBy: "\n")
        let idx = line - 1
        guard idx >= 0, idx < lines.count else { return }
        if checked {
            lines[idx] = lines[idx]
                .replacingOccurrences(of: "- [ ]", with: "- [x]")
                .replacingOccurrences(of: "* [ ]", with: "* [x]")
                .replacingOccurrences(of: "+ [ ]", with: "+ [x]")
        } else {
            lines[idx] = lines[idx]
                .replacingOccurrences(of: "- [x]", with: "- [ ]")
                .replacingOccurrences(of: "- [X]", with: "- [ ]")
                .replacingOccurrences(of: "* [x]", with: "* [ ]")
                .replacingOccurrences(of: "* [X]", with: "* [ ]")
                .replacingOccurrences(of: "+ [x]", with: "+ [ ]")
                .replacingOccurrences(of: "+ [X]", with: "+ [ ]")
        }
        workspace.currentFileText = lines.joined(separator: "\n")
    }

    private func resolveWikiLink(_ target: String) -> URL? {
        let cleaned = target.trimmingCharacters(in: .whitespaces)

        // Path-qualified link (contains "/"): try every registered vault's
        // root as the base. Matches how Claude's `[[people/josh-pigford]]`
        // answers map onto real vault-relative paths.
        if cleaned.contains("/") {
            let candidatePath = cleaned.hasSuffix(".md") ? cleaned : "\(cleaned).md"
            for location in workspace.locations {
                let candidate = location.url.appendingPathComponent(candidatePath)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }

        // Bare stem: walk the file tree and stem-match (existing behavior).
        let needle = cleaned.lowercased()
        for location in workspace.locations {
            if let hit = Self.findMatchingFile(in: location.fileTree, needle: needle) {
                return hit
            }
        }
        return nil
    }

    private static func findMatchingFile(in tree: [FileNode], needle: String) -> URL? {
        for node in tree {
            if node.isDirectory {
                if let hit = findMatchingFile(in: node.children ?? [], needle: needle) {
                    return hit
                }
            } else {
                let stem = (node.name as NSString).deletingPathExtension.lowercased()
                if stem == needle || node.name.lowercased() == needle {
                    return node.url
                }
            }
        }
        return nil
    }

    private func openMarkdownLink(_ href: String) {
        if let absoluteURL = URL(string: href), absoluteURL.scheme != nil {
            NSWorkspace.shared.open(absoluteURL)
            return
        }

        guard let currentFileURL = workspace.currentFileURL,
              let resolvedURL = URL(string: href, relativeTo: currentFileURL)?.absoluteURL else {
            return
        }

        if resolvedURL.isFileURL, workspace.openFile(at: resolvedURL) {
            return
        }

        NSWorkspace.shared.open(resolvedURL)
    }

    private func navigateToWikiLink(target: String, heading: String?, destinationMode: ViewMode) {
        for vaultIndex in workspace.activeVaultIndexes {
            guard let file = vaultIndex.resolveWikiLink(name: target) else { continue }

            let fileURL = vaultIndex.rootURL.appendingPathComponent(file.path)
            let headingLine = heading.flatMap { vaultIndex.lineNumberForHeading(in: file.id, heading: $0) }

            guard workspace.openFile(at: fileURL) else { return }

            let resolvedMode: ViewMode = editorEngine == .livePreviewExperimental ? .edit : destinationMode
            if let headingLine {
                if workspace.currentFileURL == fileURL {
                    scheduleWikiNavigation(lineNumber: headingLine, destinationMode: resolvedMode)
                } else {
                    pendingWikiNavigation = PendingWikiNavigation(
                        fileURL: fileURL,
                        lineNumber: headingLine,
                        destinationMode: resolvedMode
                    )
                }
            } else {
                workspace.currentViewMode = resolvedMode
                pendingWikiNavigation = nil
            }
            return
        }
    }

    private func applyPendingWikiNavigationIfNeeded() {
        guard let pendingWikiNavigation,
              workspace.currentFileURL == pendingWikiNavigation.fileURL else { return }
        scheduleWikiNavigation(
            lineNumber: pendingWikiNavigation.lineNumber,
            destinationMode: pendingWikiNavigation.destinationMode
        )
        self.pendingWikiNavigation = nil
    }

    private func scheduleWikiNavigation(lineNumber: Int, destinationMode: ViewMode) {
        workspace.currentViewMode = destinationMode
        let notificationName: Notification.Name = destinationMode == .preview ? .scrollPreviewToLine : .scrollEditorToLine
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: notificationName,
                object: nil,
                userInfo: ["line": lineNumber]
            )
        }
    }
}

/// Extracted modifier so MacDetailColumn.body stays inside SwiftUI's
/// type-checker budget. Handles every NotificationCenter-driven Wiki action
/// (Capture / Chat / Review / Toggle Log Sidebar).
private struct WikiNotificationObserversModifier: ViewModifier {
    @Bindable var workspace: WorkspaceManager
    @Bindable var wikiController: WikiOperationController
    @Bindable var wikiChat: WikiChatState
    @Bindable var wikiLog: WikiLogState
    @Bindable var wikiCapture: WikiCaptureState

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .wikiCapture)) { _ in
                WikiAgentCoordinator.startCapture(workspace: workspace, capture: wikiCapture)
            }
            .onReceive(NotificationCenter.default.publisher(for: .wikiChat)) { _ in
                WikiAgentCoordinator.startChat(workspace: workspace, chat: wikiChat)
            }
            .onReceive(NotificationCenter.default.publisher(for: .wikiToggleLogSidebar)) { _ in
                withAnimation(Theme.Motion.smooth) {
                    wikiLog.toggle(vaultRoot: workspace.activeLocation?.url)
                }
            }
    }
}

private struct WikiSheetsModifier: ViewModifier {
    @Bindable var workspace: WorkspaceManager
    @Bindable var wikiController: WikiOperationController
    @Bindable var wikiCapture: WikiCaptureState
    let onOperationApplied: (WikiOperation, URL) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { wikiController.isPresenting },
                set: { if !$0 { wikiController.dismiss() } }
            )) {
                WikiDiffSheet(
                    controller: wikiController,
                    onApplied: onOperationApplied
                )
            }
            .sheet(isPresented: Binding(
                get: { wikiCapture.isVisible },
                set: { if !$0 { wikiCapture.dismiss() } }
            )) {
                WikiCaptureSheet(state: wikiCapture) { text in
                    WikiAgentCoordinator.submitCapture(
                        text,
                        workspace: workspace,
                        controller: wikiController
                    )
                }
            }
    }
}

private struct LivePreviewEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Live Preview is active")
                .font(.system(size: 18, weight: .semibold))

            Text("Type or open a markdown note to test it. The active line stays editable as raw markdown, and completed constructs render once the caret moves away.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Text("Try: `# Heading`, `**bold**`, `- [ ] task`")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 24)
    }
}
