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
    @Binding var showFormatPopover: Bool

    var body: some ToolbarContent {
        // Centered: editor / preview mode picker — sits in the toolbar's
        // principal slot so it visually anchors the middle of the bar.
        ToolbarItem(placement: .principal) {
            Picker("Mode", selection: $workspace.currentViewMode) {
                Image(systemName: "pencil").tag(ViewMode.edit)
                Image(systemName: "eye").tag(ViewMode.preview)
            }
            .pickerStyle(.segmented)
            .help("Editor / Preview (⌘1 / ⌘2)")
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
                NSApp.sendAction(#selector(ClearlyTextView.toggleTodoList(_:)), to: nil, from: nil)
            } label: {
                Label("Checklist", systemImage: "checklist")
            }
            .help("Insert checklist item")
            .disabled(workspace.activeDocumentID == nil || workspace.currentViewMode != .edit)

            Menu {
                Button("Insert Link…") {
                    NSApp.sendAction(#selector(ClearlyTextView.insertLink(_:)), to: nil, from: nil)
                }
                Button("Insert Image…") {
                    NSApp.sendAction(#selector(ClearlyTextView.insertImage(_:)), to: nil, from: nil)
                }
                Button("Insert Table") {
                    NSApp.sendAction(#selector(ClearlyTextView.insertMarkdownTable(_:)), to: nil, from: nil)
                }
                Button("Insert Code Block") {
                    NSApp.sendAction(#selector(ClearlyTextView.insertCodeBlock(_:)), to: nil, from: nil)
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
    }
}

/// Detail column for the native shell — editor/preview ZStack with opacity
/// crossfade, conflict banner + find/jump overlays at the top, and the
/// outline panel mounted as an HStack sibling on the trailing edge.
struct MacDetailColumn: View {
    @Bindable var workspace: WorkspaceManager
    @ObservedObject var findState: FindState
    @ObservedObject var outlineState: OutlineState
    @ObservedObject var backlinksState: BacklinksState
    @ObservedObject var jumpToLineState: JumpToLineState
    @Binding var positionSyncID: String
    @Binding var showFormatPopover: Bool

    @StateObject private var fileWatcher = FileWatcher()
    @State private var isFullscreen = false

    @AppStorage("editorFontSize") private var fontSize: Double = 16
    @AppStorage("previewFontFamily") private var previewFontFamily: String = "sanFrancisco"
    @AppStorage("contentWidth") private var contentWidth: String = "default"
    @AppStorage("showLineNumbers") private var showLineNumbers: Bool = false

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
        }
        .animation(Theme.Motion.smooth, value: outlineState.isVisible)
        .navigationTitle(documentTitle)
        .onAppear {
            outlineState.parseHeadings(from: workspace.currentFileText)
            backlinksState.update(for: workspace.currentFileURL, using: workspace.activeVaultIndexes)
            isFullscreen = NSApp.mainWindow?.styleMask.contains(.fullScreen) ?? false
            setupFileWatcher()
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
            outlineState.parseHeadings(from: workspace.currentFileText)
            backlinksState.update(for: workspace.currentFileURL, using: workspace.activeVaultIndexes)
            setupFileWatcher()
        }
        .onChange(of: workspace.currentFileText) { _, text in
            outlineState.parseHeadings(from: text)
        }
        .onChange(of: workspace.currentFileURL) { _, _ in
            setupFileWatcher()
        }
        .modifier(FocusedValuesModifier(
            workspace: workspace,
            findState: findState,
            outlineState: outlineState,
            backlinksState: backlinksState,
            jumpToLineState: jumpToLineState
        ))
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
                editorPane
                    .opacity(workspace.currentViewMode == .edit ? 1 : 0)
                    .allowsHitTesting(workspace.currentViewMode == .edit)
                previewPane
                    .opacity(workspace.currentViewMode == .preview ? 1 : 0)
                    .allowsHitTesting(workspace.currentViewMode == .preview)
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
            onWikiLinkClicked: { target, _ in
                // Basic wiki-link navigation: try to open matching file by name.
                if let url = resolveWikiLink(target) {
                    workspace.openFile(at: url)
                }
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
        let needle = target.lowercased()
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
}

