import SwiftUI

extension Notification.Name {
    static let scrollEditorToLine = Notification.Name("scrollEditorToLine")
    static let scrollPreviewToLine = Notification.Name("scrollPreviewToLine")
    static let flushEditorBuffer = Notification.Name("flushEditorBuffer")
    static let navigateWikiLink = Notification.Name("navigateWikiLink")
}

struct ViewModeKey: FocusedValueKey {
    typealias Value = Binding<ViewMode>
}

struct DocumentTextKey: FocusedValueKey {
    typealias Value = String
}

struct DocumentFileURLKey: FocusedValueKey {
    typealias Value = URL
}

struct FindStateKey: FocusedValueKey {
    typealias Value = FindState
}

struct OutlineStateKey: FocusedValueKey {
    typealias Value = OutlineState
}

struct BacklinksStateKey: FocusedValueKey {
    typealias Value = BacklinksState
}

struct JumpToLineStateKey: FocusedValueKey {
    typealias Value = JumpToLineState
}

extension FocusedValues {
    var viewMode: Binding<ViewMode>? {
        get { self[ViewModeKey.self] }
        set { self[ViewModeKey.self] = newValue }
    }
    var documentText: String? {
        get { self[DocumentTextKey.self] }
        set { self[DocumentTextKey.self] = newValue }
    }
    var documentFileURL: URL? {
        get { self[DocumentFileURLKey.self] }
        set { self[DocumentFileURLKey.self] = newValue }
    }
    var findState: FindState? {
        get { self[FindStateKey.self] }
        set { self[FindStateKey.self] = newValue }
    }
    var outlineState: OutlineState? {
        get { self[OutlineStateKey.self] }
        set { self[OutlineStateKey.self] = newValue }
    }
    var backlinksState: BacklinksState? {
        get { self[BacklinksStateKey.self] }
        set { self[BacklinksStateKey.self] = newValue }
    }
    var jumpToLineState: JumpToLineState? {
        get { self[JumpToLineStateKey.self] }
        set { self[JumpToLineStateKey.self] = newValue }
    }
}

struct FocusedValuesModifier: ViewModifier {
    @Bindable var workspace: WorkspaceManager
    var findState: FindState
    var outlineState: OutlineState
    var backlinksState: BacklinksState
    var jumpToLineState: JumpToLineState

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.viewMode, $workspace.currentViewMode)
            .focusedSceneValue(\.documentText, workspace.currentFileText)
            .focusedSceneValue(\.documentFileURL, workspace.currentFileURL)
            .focusedSceneValue(\.findState, findState)
            .focusedSceneValue(\.outlineState, outlineState)
            .focusedSceneValue(\.backlinksState, backlinksState)
            .focusedSceneValue(\.jumpToLineState, jumpToLineState)
    }
}

struct HiddenToolbarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content
        }
    }
}

struct ContentView: View {
    private struct PendingWikiNavigation {
        let fileURL: URL
        let lineNumber: Int
        let destinationMode: ViewMode
    }

    @Bindable var workspace: WorkspaceManager
    @State private var positionSyncID = UUID().uuidString
    @State private var pendingWikiNavigation: PendingWikiNavigation?
    @AppStorage("editorFontSize") private var fontSize: Double = 16
    @AppStorage("previewFontFamily") private var previewFontFamily = "sanFrancisco"
    @StateObject private var findState = FindState()
    @StateObject private var fileWatcher = FileWatcher()
    @StateObject private var outlineState = OutlineState()
    @StateObject private var backlinksState = BacklinksState()
    @StateObject private var jumpToLineState = JumpToLineState()
    @AppStorage("showLineNumbers") private var showLineNumbers = false
    @State private var isFullscreen = false
    @Environment(\.colorScheme) private var colorScheme

    private var hasTabBar: Bool { workspace.openDocuments.count >= 2 }

    private var contentExtraTopInset: CGFloat {
        var inset: CGFloat = hasTabBar ? 16 : 0
        if isFullscreen { inset += 16 }
        return inset
    }

    private var editorPane: some View {
        let editorFontSize = CGFloat(fontSize)
        let fileURL = workspace.currentFileURL
        return EditorView(text: $workspace.currentFileText, fontSize: editorFontSize, fileURL: fileURL, mode: workspace.currentViewMode, positionSyncID: positionSyncID, findState: findState, outlineState: outlineState, extraTopInset: contentExtraTopInset, showLineNumbers: showLineNumbers, jumpToLineState: jumpToLineState)
    }

    private var previewPane: some View {
        let editorFontSize = CGFloat(fontSize)
        let fileURL = workspace.currentFileURL
        let _ = workspace.vaultIndexRevision
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
            fontSize: editorFontSize,
            fontFamily: previewFontFamily,
            mode: workspace.currentViewMode,
            positionSyncID: positionSyncID,
            fileURL: fileURL,
            findState: findState,
            outlineState: outlineState,
            onTaskToggle: { [workspace] line, checked in
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
            },
            onClickToSource: { [workspace] line in
                workspace.currentViewMode = .edit
                NotificationCenter.default.post(name: .scrollEditorToLine, object: nil, userInfo: ["line": line])
            },
            onWikiLinkClicked: { target, heading in
                navigateToWikiLink(target: target, heading: heading, destinationMode: .preview)
            },
            onTagClicked: { tagName in
                NotificationCenter.default.post(
                    name: .init("ClearlyFilterByTag"),
                    object: nil,
                    userInfo: ["tag": tagName]
                )
            },
            wikiFileNames: allWikiFileNames,
            extraTopInset: contentExtraTopInset
        )
    }

    // MARK: - Bottom toolbar (Things-style)

    private func bottomBar(words: Int, chars: Int) -> some View {
        HStack(spacing: 0) {
            // Edit/Preview on the left
            ClearlySegmentedControl(
                selection: $workspace.currentViewMode,
                items: [
                    (value: .edit, icon: "pencil", label: "Edit"),
                    (value: .preview, icon: "eye", label: "Preview")
                ]
            )
            .padding(.leading, 12)

            Spacer()

            // Word/char count centered
            HStack(spacing: 0) {
                Text("\(words) words")
                Text(" \u{00B7} ")
                Text("\(chars) characters")
            }
            .font(.system(size: 11))
            .tracking(0.3)
            .foregroundStyle(.tertiary)

            Spacer()

            // Right-side actions
            HStack(spacing: 4) {
                if workspace.activeDocumentID != nil {
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
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(ClearlyToolbarButtonStyle())
                    .help("Copy document content")
                }

                Button {
                    withAnimation(Theme.Motion.smooth) {
                        backlinksState.toggle()
                    }
                } label: {
                    Image(systemName: "link")
                }
                .buttonStyle(ClearlyToolbarButtonStyle(isActive: backlinksState.isVisible))
                .help("Backlinks (Shift+Cmd+B)")

                Button {
                    withAnimation(Theme.Motion.smooth) {
                        outlineState.toggle()
                    }
                } label: {
                    Image(systemName: "list.bullet.indent")
                }
                .buttonStyle(ClearlyToolbarButtonStyle(isActive: outlineState.isVisible))
                .help("Document Outline (Shift+Cmd+O)")

                Button {
                    findState.present()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(ClearlyToolbarButtonStyle())
                .help("Find (Cmd+F)")
            }
            .padding(.trailing, 12)
        }
        .frame(height: 40)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var mainContent: some View {
        let text = workspace.currentFileText
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        let chars = text.count

        return VStack(spacing: 0) {
            if findState.isVisible {
                FindBarView(findState: findState)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
            }
            if jumpToLineState.isVisible {
                JumpToLineBar(state: jumpToLineState)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
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
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
                BacklinksView(backlinksState: backlinksState) { backlink in
                    let fileURL = backlink.vaultRootURL.appendingPathComponent(backlink.sourcePath)
                    if workspace.openFile(at: fileURL) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            NotificationCenter.default.post(
                                name: .scrollEditorToLine,
                                object: nil,
                                userInfo: ["line": backlink.lineNumber]
                            )
                        }
                    }
                } onLink: { backlink in
                    linkBacklink(backlink)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: 200)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            bottomBar(words: words, chars: chars)
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Theme.backgroundColorSwiftUI)
    }

    var body: some View {
        HStack(spacing: 0) {
            mainContent

            if outlineState.isVisible {
                Rectangle()
                    .fill(Color.primary.opacity(colorScheme == .dark ? Theme.separatorOpacityDark : Theme.separatorOpacity))
                    .frame(width: 1)
                OutlineView(outlineState: outlineState)
                    .frame(width: 200)
            }
        }
            .animation(Theme.Motion.smooth, value: workspace.currentViewMode)
            .modifier(FocusedValuesModifier(workspace: workspace, findState: findState, outlineState: outlineState, backlinksState: backlinksState, jumpToLineState: jumpToLineState))
            .onAppear {
                setupFileWatcher()
                outlineState.parseHeadings(from: workspace.currentFileText)
                backlinksState.update(for: workspace.currentFileURL, using: workspace.activeVaultIndexes)
                isFullscreen = NSApp.mainWindow?.styleMask.contains(.fullScreen) ?? false
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
                isFullscreen = true
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
                isFullscreen = false
            }
            .onChange(of: workspace.activeDocumentID) { _, newID in
                positionSyncID = UUID().uuidString
                findState.isVisible = false
                jumpToLineState.dismiss()
                setupFileWatcher()
                outlineState.parseHeadings(from: workspace.currentFileText)
                backlinksState.update(for: workspace.currentFileURL, using: workspace.activeVaultIndexes)
                applyPendingWikiNavigationIfNeeded()
            }
            .onChange(of: workspace.currentViewMode) { _, newMode in
                guard newMode != .edit else { return }
                jumpToLineState.dismiss()
            }
            .onChange(of: workspace.currentFileURL) { _, _ in
                setupFileWatcher()
            }
            .onChange(of: workspace.currentFileText) { _, newText in
                workspace.contentDidChange()
                fileWatcher.updateCurrentText(newText)
                outlineState.parseHeadings(from: newText)
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
                    jumpToLineState.present()
                }
            }
            .onChange(of: workspace.vaultIndexRevision) { _, _ in
                backlinksState.update(for: workspace.currentFileURL, using: workspace.activeVaultIndexes)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateWikiLink)) { notification in
                guard let target = notification.userInfo?["target"] as? String else { return }
                let heading = notification.userInfo?["heading"] as? String
                navigateToWikiLink(target: target, heading: heading, destinationMode: .edit)
            }
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

    private func linkBacklink(_ backlink: Backlink) {
        let fileURL = backlink.vaultRootURL.appendingPathComponent(backlink.sourcePath)
        guard workspace.insertWikiLink(
            in: fileURL,
            matching: backlinksState.currentFilename,
            linkTarget: backlinksState.currentLinkTarget,
            atLine: backlink.lineNumber
        ) else { return }

        backlinksState.removeUnlinkedMention(backlink)
    }

    private func navigateToWikiLink(target: String, heading: String?, destinationMode: ViewMode) {
        for vaultIndex in workspace.activeVaultIndexes {
            guard let file = vaultIndex.resolveWikiLink(name: target) else { continue }

            let fileURL = vaultIndex.rootURL.appendingPathComponent(file.path)
            let headingLine = heading.flatMap { vaultIndex.lineNumberForHeading(in: file.id, heading: $0) }

            guard workspace.openFile(at: fileURL) else { return }

            if let headingLine {
                if workspace.currentFileURL == fileURL {
                    scheduleWikiNavigation(lineNumber: headingLine, destinationMode: destinationMode)
                } else {
                    pendingWikiNavigation = PendingWikiNavigation(
                        fileURL: fileURL,
                        lineNumber: headingLine,
                        destinationMode: destinationMode
                    )
                }
            } else {
                workspace.currentViewMode = destinationMode
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
