import SwiftUI

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
        return PreviewView(markdown: workspace.currentFileText, fontSize: editorFontSize, mode: mode, positionSyncID: positionSyncID, fileURL: fileURL, findState: findState, outlineState: outlineState)
    }

    private var mainContent: some View {
        let text = workspace.currentFileText
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        let chars = text.count

        return VStack(spacing: 0) {
            if findState.isVisible {
                FindBarView(findState: findState)
                Divider()
            }
            ZStack {
                editorPane
                    .opacity(mode == .edit ? 1 : 0)
                    .allowsHitTesting(mode == .edit)
                previewPane
                    .opacity(mode == .preview ? 1 : 0)
                    .allowsHitTesting(mode == .preview)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if mode != .preview {
                statusBar(words: words, chars: chars)
            }
        }
        .inspector(isPresented: $outlineState.isVisible) {
            OutlineView(outlineState: outlineState)
                .inspectorColumnWidth(min: 180, ideal: 200, max: 280)
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Theme.backgroundColorSwiftUI)
    }

    @ToolbarContentBuilder
    private var contentToolbar: some ToolbarContent {
        Group {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $mode) {
                    Image(systemName: "pencil")
                        .tag(ViewMode.edit)
                    Image(systemName: "eye")
                        .tag(ViewMode.preview)
                }
                .pickerStyle(.segmented)
                .frame(width: 100)
                .help("Toggle Editor/Preview (Cmd+1/Cmd+2)")
            }
            if workspace.activeDocumentID != nil {
                ToolbarItem(placement: .automatic) {
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
                    .help("Copy document content")
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        outlineState.toggle()
                    }
                } label: {
                    Image(systemName: "list.bullet.indent")
                }
                .help("Document Outline (Shift+Cmd+O)")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    findState.present()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Find (Cmd+F)")
            }
        }
    }

    var body: some View {
        mainContent
            .onChange(of: mode) { _, newMode in
                UserDefaults.standard.set(newMode.rawValue, forKey: "viewMode")
            }
            .toolbar { contentToolbar }
            .modifier(HiddenToolbarBackground())
            .animation(.easeInOut(duration: 0.15), value: mode)
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
    }

    private func statusBar(words: Int, chars: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(words) words")
            Text("\(chars) characters")
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.backgroundColorSwiftUI)
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
