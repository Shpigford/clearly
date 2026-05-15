#if os(iOS)
import SwiftUI
import ClearlyCore

/// Per-document scene root for the iOS app. One per `DocumentGroup` window.
/// Hosts the editor, preview (read-only), find overlay, and outline sheet.
struct DocumentDetailBody: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @State private var viewMode: ViewMode = .edit
    @State private var showOutline = false
    @StateObject private var outlineState = OutlineState()
    @StateObject private var findState = FindState()
    @AppStorage("editorFontSize") private var fontSize: Double = 16
    @AppStorage("previewFontFamily") private var previewFontFamily: String = "sanFrancisco"
    @AppStorage("hideFrontmatterInPreview") private var hideFrontmatterInPreview: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if findState.isVisible {
                FindOverlay_iOS(findState: findState)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            content
        }
        .animation(Theme.Motion.smooth, value: findState.isVisible)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewMode) { _, newMode in
            findState.activeMode = newMode
            if newMode != .edit, findState.isVisible {
                findState.dismiss()
            }
        }
        .onAppear {
            findState.activeMode = viewMode
            outlineState.parseHeadings(from: document.text)
        }
        .onChange(of: document.text) { _, newText in
            outlineState.parseHeadings(from: newText)
        }
        .watchExternalChanges(fileURL: fileURL, text: $document.text)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewMode = (viewMode == .edit) ? .preview : .edit
                } label: {
                    Image(systemName: viewMode == .edit ? "eye" : "square.and.pencil")
                }
                .accessibilityLabel(viewMode == .edit ? "Show preview" : "Show editor")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    findState.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)
                .accessibilityLabel("Find in note")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showOutline = true } label: {
                    Image(systemName: "list.bullet.indent")
                }
                .accessibilityLabel("Outline")
            }
        }
        .sheet(isPresented: $showOutline) {
            OutlineSheet_iOS(outlineState: outlineState, onJump: jumpToHeading)
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            EditorView_iOS(
                text: $document.text,
                documentURL: fileURL,
                outlineState: outlineState,
                findState: findState
            )
            .opacity(viewMode == .edit ? 1 : 0)
            .allowsHitTesting(viewMode == .edit)

            PreviewView_iOS(
                markdown: document.text,
                fileURL: fileURL,
                fontSize: CGFloat(fontSize) + 2,
                fontFamily: previewFontFamily,
                hideFrontmatter: hideFrontmatterInPreview,
                isVisible: viewMode == .preview,
                onTaskToggle: handleTaskToggle
            )
            .opacity(viewMode == .preview ? 1 : 0)
            .allowsHitTesting(viewMode == .preview)
        }
    }

    private func jumpToHeading(_ heading: HeadingItem) {
        viewMode = .edit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            outlineState.scrollToRange?(heading.range)
        }
    }

    private func handleTaskToggle(_ line: Int, _ checked: Bool) {
        var lines = document.text.components(separatedBy: "\n")
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
        document.text = lines.joined(separator: "\n")
    }
}
#endif
