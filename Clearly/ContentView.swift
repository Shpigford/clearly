import SwiftUI

enum ViewMode: String, CaseIterable {
    case edit
    case sideBySide
    case preview
}

struct ViewModeKey: FocusedValueKey {
    typealias Value = Binding<ViewMode>
}

extension FocusedValues {
    var viewMode: Binding<ViewMode>? {
        get { self[ViewModeKey.self] }
        set { self[ViewModeKey.self] = newValue }
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
    @State private var mode: ViewMode
    @AppStorage("editorFontSize") private var fontSize: Double = 16
    @State private var widthBeforeSplit: CGFloat?
    @StateObject private var scrollSync = ScrollSync()

    init(document: Binding<MarkdownDocument>) {
        self._document = document
        let storedMode = UserDefaults.standard.string(forKey: "viewMode")
        self._mode = State(initialValue: ViewMode(rawValue: storedMode ?? "") ?? .edit)
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
        Group {
            switch mode {
            case .edit:
                EditorView(text: $document.text, fontSize: CGFloat(fontSize))
            case .sideBySide:
                HSplitView {
                    EditorView(text: $document.text, fontSize: CGFloat(fontSize), scrollSync: scrollSync)
                    PreviewView(markdown: document.text, fontSize: CGFloat(fontSize), scrollSync: scrollSync)
                }
            case .preview:
                PreviewView(markdown: document.text, fontSize: CGFloat(fontSize))
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
                if mode != .preview {
                    Button {
                        NSApp.sendAction(#selector(ClearlyTextView.showFindPanel(_:)), to: nil, from: nil)
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .help("Find (Cmd+F)")
                }
            }
        }
        .modifier(HiddenToolbarBackground())
        .animation(nil, value: mode)
        .focusedSceneValue(\.viewMode, $mode)
    }
}
