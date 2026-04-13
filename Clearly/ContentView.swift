import SwiftUI

extension Notification.Name {
    static let scrollEditorToLine = Notification.Name("scrollEditorToLine")
    static let flushEditorBuffer = Notification.Name("flushEditorBuffer")
}

enum ViewMode: String, CaseIterable {
    case edit
    case preview
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
}

struct FocusedValuesModifier: ViewModifier {
    var workspace: WorkspaceManager
    @Binding var mode: ViewMode
    var findState: FindState
    var outlineState: OutlineState

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.viewMode, $mode)
            .focusedSceneValue(\.documentText, workspace.currentFileText)
            .focusedSceneValue(\.documentFileURL, workspace.currentFileURL)
            .focusedSceneValue(\.findState, findState)
            .focusedSceneValue(\.outlineState, outlineState)
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
    @Bindable var workspace: WorkspaceManager
    @State private var mode: ViewMode
    @State private var positionSyncID = UUID().uuidString
    @AppStorage("editorFontSize") private var fontSize: Double = 16
    @StateObject private var findState = FindState()
    @StateObject private var fileWatcher = FileWatcher()
    @StateObject private var outlineState = OutlineState()

    init(workspace: WorkspaceManager) {
        self.workspace = workspace
        let storedMode = UserDefaults.standard.string(forKey: "viewMode")
        self._mode = State(initialValue: ViewMode(rawValue: storedMode ?? "") ?? .edit)
    }

    private var editorPane: some View {
        let editorFontSize = CGFloat(fontSize)
        let fileURL = workspace.currentFileURL
        return EditorView(text: $workspace.currentFileText, fontSize: editorFontSize, fileURL: fileURL, mode: mode, positionSyncID: positionSyncID, findState: findState, outlineState: outlineState)
    }

    private var previewPane: some View {
        let editorFontSize = CGFloat(fontSize)
        let fileURL = workspace.currentFileURL
        return PreviewView(
            markdown: workspace.currentFileText,
            fontSize: editorFontSize,
            mode: mode,
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
            onClickToSource: { line in
                mode = .edit
                // Post a notification that EditorView can observe to scroll to line
                NotificationCenter.default.post(name: .scrollEditorToLine, object: nil, userInfo: ["line": line])
            }
        )
    }

    // MARK: - Bottom toolbar (Things-style)

    private func bottomBar(words: Int, chars: Int) -> some View {
        HStack(spacing: 0) {
            // Edit/Preview on the left
            ClearlySegmentedControl(
                selection: $mode,
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
            ZStack {
                editorPane
                    .opacity(mode == .edit ? 1 : 0)
                    .allowsHitTesting(mode == .edit)
                previewPane
                    .opacity(mode == .preview ? 1 : 0)
                    .allowsHitTesting(mode == .preview)
            }

            bottomBar(words: words, chars: chars)
        }
        .inspector(isPresented: $outlineState.isVisible) {
            OutlineView(outlineState: outlineState)
                .inspectorColumnWidth(min: 180, ideal: 200, max: 280)
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Theme.backgroundColorSwiftUI)
    }

    var body: some View {
        mainContent
            .onChange(of: mode) { _, newMode in
                UserDefaults.standard.set(newMode.rawValue, forKey: "viewMode")
            }
            .animation(Theme.Motion.smooth, value: mode)
            .modifier(FocusedValuesModifier(workspace: workspace, mode: $mode, findState: findState, outlineState: outlineState))
            .onAppear {
                setupFileWatcher()
                outlineState.parseHeadings(from: workspace.currentFileText)
            }
            .onChange(of: workspace.activeDocumentID) { _, newID in
                positionSyncID = UUID().uuidString
                findState.isVisible = false
                setupFileWatcher()
                outlineState.parseHeadings(from: workspace.currentFileText)
                // New untitled docs always open in edit mode
                if let newID, let doc = workspace.openDocuments.first(where: { $0.id == newID }), doc.isUntitled {
                    mode = .edit
                }
            }
            .onChange(of: workspace.currentFileURL) { _, _ in
                setupFileWatcher()
            }
            .onChange(of: workspace.currentFileText) { _, newText in
                workspace.contentDidChange()
                fileWatcher.updateCurrentText(newText)
                outlineState.parseHeadings(from: newText)
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("ClearlySetViewMode"))) { notification in
                if let modeStr = notification.object as? String, let newMode = ViewMode(rawValue: modeStr) {
                    mode = newMode
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("ClearlyToggleOutline"))) { _ in
                withAnimation(Theme.Motion.smooth) {
                    outlineState.toggle()
                }
            }
    }

    private func setupFileWatcher() {
        guard let url = workspace.currentFileURL else {
            fileWatcher.watch(nil, currentText: nil)
            return
        }
        fileWatcher.onChange = { [workspace] newText in
            workspace.externalFileDidChange(newText)
        }
        fileWatcher.watch(url, currentText: workspace.currentFileText)
    }
}
