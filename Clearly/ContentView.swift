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

// MARK: - Window Frame Persistence

/// Sets NSWindow.frameAutosaveName so macOS automatically saves/restores window size and position.
/// Uses a per-file autosave name so each document remembers its own window frame.
struct WindowFrameSaver: NSViewRepresentable {
    let fileURL: URL?

    final class Coordinator {
        var autosaveName: String?
    }

    private var autosaveName: String {
        fileURL?.absoluteString ?? "ClearlyUntitledWindow"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func applyAutosaveName(
        to window: NSWindow,
        coordinator: Coordinator,
        persistCurrentFrame: Bool
    ) {
        guard coordinator.autosaveName != autosaveName else { return }
        coordinator.autosaveName = autosaveName
        window.setFrameAutosaveName(autosaveName)
        if persistCurrentFrame {
            window.saveFrame(usingName: autosaveName)
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                applyAutosaveName(
                    to: window,
                    coordinator: context.coordinator,
                    persistCurrentFrame: false
                )
                // Ensure the document window comes to front after opening.
                activateDocumentApp()
                window.makeKeyAndOrderFront(nil)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        applyAutosaveName(
            to: window,
            coordinator: context.coordinator,
            persistCurrentFrame: context.coordinator.autosaveName != nil
        )
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
    @Binding var document: MarkdownDocument
    let fileURL: URL?
    @State private var mode: ViewMode
    @State private var positionSyncID = UUID().uuidString
    @AppStorage("editorFontSize") private var fontSize: Double = 16
    @StateObject private var findState = FindState()
    @StateObject private var fileWatcher = FileWatcher()
    @StateObject private var outlineState = OutlineState()

    init(document: Binding<MarkdownDocument>, fileURL: URL? = nil) {
        self._document = document
        self.fileURL = fileURL
        let storedMode = UserDefaults.standard.string(forKey: "viewMode")
        self._mode = State(initialValue: ViewMode(rawValue: storedMode ?? "") ?? .edit)
        DiagnosticLog.log("Document opened: \(fileURL?.lastPathComponent ?? "untitled")")
    }

    private var wordCount: Int {
        document.text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var characterCount: Int {
        document.text.count
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                if findState.isVisible {
                    FindBarView(findState: findState)
                    Divider()
                }
                ZStack {
                    EditorView(text: $document.text, fontSize: CGFloat(fontSize), fileURL: fileURL, mode: mode, positionSyncID: positionSyncID, findState: findState, outlineState: outlineState)
                        .opacity(mode == .edit ? 1 : 0)
                        .allowsHitTesting(mode == .edit)
                    PreviewView(markdown: document.text, fontSize: CGFloat(fontSize), mode: mode, positionSyncID: positionSyncID, fileURL: fileURL, findState: findState, outlineState: outlineState)
                        .opacity(mode == .preview ? 1 : 0)
                        .allowsHitTesting(mode == .preview)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if mode != .preview {
                    HStack(spacing: 12) {
                        Text("\(wordCount) words")
                        Text("\(characterCount) characters")
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Theme.backgroundColorSwiftUI)
                }
            }

            if outlineState.isVisible {
                Divider()
                OutlineView(outlineState: outlineState)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Theme.backgroundColorSwiftUI)
        .onChange(of: mode) { _, newMode in
            UserDefaults.standard.set(newMode.rawValue, forKey: "viewMode")
        }
        .toolbar {
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
        .modifier(HiddenToolbarBackground())
        .background(WindowFrameSaver(fileURL: fileURL))
        .animation(.easeInOut(duration: 0.15), value: mode)
        .focusedSceneValue(\.viewMode, $mode)
        .focusedSceneValue(\.documentText, document.text)
        .focusedSceneValue(\.documentFileURL, fileURL)
        .focusedSceneValue(\.findState, findState)
        .focusedSceneValue(\.outlineState, outlineState)
        .onAppear {
            fileWatcher.onChange = { [self] newText in
                document.text = newText
            }
            fileWatcher.watch(fileURL, currentText: document.text)
            outlineState.parseHeadings(from: document.text)
        }
        .onChange(of: fileURL) { _, newURL in
            fileWatcher.watch(newURL, currentText: document.text)
        }
        .onChange(of: document.text) { _, newText in
            fileWatcher.updateCurrentText(newText)
            outlineState.parseHeadings(from: newText)
        }
    }
}
