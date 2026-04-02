import SwiftUI

enum ViewMode: String, CaseIterable {
    case edit
    case sideBySide
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
    @AppStorage("editorFontSize") private var fontSize: Double = 16
    @State private var widthBeforeSplit: CGFloat?
    @StateObject private var scrollSync = ScrollSync()
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

    private func animateWindowFrame(_ window: NSWindow, to newFrame: NSRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if findState.isVisible {
                FindBarView(findState: findState)
                Divider()
            }
            Group {
                switch mode {
                case .edit:
                    EditorView(text: $document.text, fontSize: CGFloat(fontSize), fileURL: fileURL, findState: findState, outlineState: outlineState)
                case .sideBySide:
                    HSplitView {
                        EditorView(text: $document.text, fontSize: CGFloat(fontSize), fileURL: fileURL, scrollSync: scrollSync, findState: findState, outlineState: outlineState)
                        PreviewView(markdown: document.text, fontSize: CGFloat(fontSize), scrollSync: scrollSync, fileURL: fileURL, outlineState: outlineState)
                    }
                case .preview:
                    PreviewView(markdown: document.text, fontSize: CGFloat(fontSize), fileURL: fileURL, findState: findState, outlineState: outlineState)
                }
            }
        }
        .frame(minWidth: mode == .sideBySide ? 1000 : 500, minHeight: 400)
        .background(Theme.backgroundColorSwiftUI)
        .onChange(of: mode) { _, newMode in
            UserDefaults.standard.set(newMode.rawValue, forKey: "viewMode")
            guard let window = NSApp.keyWindow else { return }
            let frame = window.frame
            if newMode == .sideBySide {
                if frame.width < 1200 {
                    widthBeforeSplit = frame.width
                    let newWidth: CGFloat = 1200
                    let delta = newWidth - frame.width
                    let newFrame = NSRect(
                        x: frame.origin.x - delta / 2,
                        y: frame.origin.y,
                        width: newWidth,
                        height: frame.height
                    )
                    animateWindowFrame(window, to: newFrame)
                }
            } else if let restored = widthBeforeSplit {
                widthBeforeSplit = nil
                let delta = frame.width - restored
                let newFrame = NSRect(
                    x: frame.origin.x + delta / 2,
                    y: frame.origin.y,
                    width: restored,
                    height: frame.height
                )
                animateWindowFrame(window, to: newFrame)
            }
        }
        .safeAreaInset(edge: .trailing, spacing: 0) {
            if outlineState.isVisible {
                OutlineView(outlineState: outlineState)
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
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Mode", selection: $mode) {
                    Image(systemName: "pencil")
                        .tag(ViewMode.edit)
                    Image(systemName: "rectangle.split.2x1")
                        .tag(ViewMode.sideBySide)
                    Image(systemName: "eye")
                        .tag(ViewMode.preview)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
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
        .animation(nil, value: mode)
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
