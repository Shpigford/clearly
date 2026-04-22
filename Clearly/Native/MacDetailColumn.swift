import SwiftUI
import AppKit
import ClearlyCore

/// Detail column for the native shell — Apple-Notes-style unified toolbar,
/// editor/preview ZStack with opacity crossfade, conflict banner +
/// find/jump overlays at the top, and outline/backlinks mounted on a
/// native `.inspector()` trailing pane.
struct MacDetailColumn: View {
    @Bindable var workspace: WorkspaceManager
    @StateObject private var findState = FindState()
    @StateObject private var outlineState = OutlineState()
    @StateObject private var backlinksState = BacklinksState()
    @StateObject private var jumpToLineState = JumpToLineState()
    @StateObject private var fileWatcher = FileWatcher()

    @State private var positionSyncID: String = UUID().uuidString
    @State private var showFormatPopover = false
    @State private var isFullscreen = false

    @AppStorage("editorFontSize") private var fontSize: Double = 16
    @AppStorage("previewFontFamily") private var previewFontFamily: String = "sanFrancisco"
    @AppStorage("contentWidth") private var contentWidth: String = "default"
    @AppStorage("showLineNumbers") private var showLineNumbers: Bool = false

    var body: some View {
        Group {
            if workspace.activeDocumentID == nil {
                emptyState
            } else {
                editorPreviewStack
            }
        }
        .navigationTitle(documentTitle)
        .toolbar { detailToolbar }
        .inspector(isPresented: outlineBinding) {
            OutlineView(outlineState: outlineState)
                .inspectorColumnWidth(min: 200, ideal: 240, max: 360)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            outlineState.toggle()
                        } label: {
                            Label("Close Outline", systemImage: "sidebar.right")
                        }
                    }
                }
        }
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
            onClickToSource: { [workspace] line in
                workspace.currentViewMode = .edit
                NotificationCenter.default.post(
                    name: .scrollEditorToLine, object: nil,
                    userInfo: ["line": line]
                )
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

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        // Format cluster — left of the toolbar, next to the sidebar toggle
        // SwiftUI contributes automatically.
        ToolbarItemGroup(placement: .navigation) {
            Picker("Mode", selection: $workspace.currentViewMode) {
                Image(systemName: "pencil").tag(ViewMode.edit)
                Image(systemName: "eye").tag(ViewMode.preview)
            }
            .pickerStyle(.segmented)
            .help("Editor / Preview (⌘1 / ⌘2)")

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
        }

        // Panel + share cluster — right side of the toolbar
        ToolbarItemGroup(placement: .primaryAction) {
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

    private var outlineBinding: Binding<Bool> {
        Binding(
            get: { outlineState.isVisible },
            set: { newValue in
                if newValue != outlineState.isVisible { outlineState.toggle() }
            }
        )
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

