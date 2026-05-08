import SwiftUI
import AppKit
import ClearlyCore

/// Per-document scene root: hosts the editor / preview, find bar, jump-to-line bar,
/// outline panel, status bar, and the toolbar mode picker. One instance per
/// `DocumentGroup` window.
struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @State private var viewMode: ViewMode = .edit
    @StateObject private var outlineState = OutlineState()
    @StateObject private var findState = FindState()
    @StateObject private var jumpToLineState = JumpToLineState()
    @StateObject private var statusBarState = StatusBarState()

    @AppStorage("editorFontSize") private var fontSize: Double = 12
    @AppStorage("previewFontFamily") private var previewFontFamily: String = "sanFrancisco"
    @AppStorage("contentWidth") private var contentWidth: String = "off"
    @AppStorage("showLineNumbers") private var showLineNumbers: Bool = false

    /// Stable per-window key for ScrollBridge / SelectionBridge. Re-keyed on
    /// document URL change so two windows on different files don't collide.
    @State private var positionSyncID: String = UUID().uuidString

    private var contentWidthEm: CGFloat? {
        switch contentWidth {
        case "narrow": return 50
        case "medium": return 65
        case "wide": return 80
        default: return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if findState.isVisible {
                FindBarView(findState: findState)
                Divider()
            }
            if jumpToLineState.isVisible {
                JumpToLineBar(state: jumpToLineState)
                Divider()
            }

            HStack(spacing: 0) {
                mainPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if outlineState.isVisible {
                    OutlineView(outlineState: outlineState, isEditorVisible: viewMode == .edit)
                        .frame(width: 240)
                }
            }

            if statusBarState.isVisible {
                Divider()
                StatusBar(state: statusBarState)
            }
        }
        .frame(minWidth: 600, minHeight: 360)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $viewMode) {
                    Text("Editor").tag(ViewMode.edit)
                    Text("Preview").tag(ViewMode.preview)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    outlineState.isVisible.toggle()
                } label: {
                    Image(systemName: "list.bullet.indent")
                }
                .help("Toggle Outline")
            }
        }
        .focusedSceneValue(\.findState, findState)
        .focusedSceneValue(\.outlineState, outlineState)
        .focusedSceneValue(\.statusBarState, statusBarState)
        .focusedSceneValue(\.viewMode, $viewMode)
        .focusedSceneValue(\.exportPDFAction) { exportPDF() }
        .focusedSceneValue(\.printDocumentAction) { printDocument() }
        .onAppear {
            outlineState.parseHeadings(from: document.text)
            statusBarState.updateText(document.text)
        }
        .onChange(of: document.text) { _, newText in
            outlineState.parseHeadings(from: newText)
            statusBarState.updateText(newText)
        }
        .onChange(of: fileURL) { _, _ in
            // Re-key bridges when the document is saved/renamed so a new
            // file's scroll position doesn't inherit the old fraction.
            positionSyncID = UUID().uuidString
        }
    }

    @ViewBuilder
    private var mainPane: some View {
        ZStack {
            EditorView(
                text: $document.text,
                fontSize: CGFloat(fontSize),
                fileURL: fileURL,
                mode: viewMode,
                positionSyncID: positionSyncID,
                findState: findState,
                outlineState: outlineState,
                showLineNumbers: showLineNumbers,
                jumpToLineState: jumpToLineState,
                statusBarState: statusBarState,
                contentWidthEm: contentWidthEm
            )
            .opacity(viewMode == .edit ? 1 : 0)
            .allowsHitTesting(viewMode == .edit)

            PreviewView(
                markdown: document.text,
                fontSize: CGFloat(fontSize) + 4,
                fontFamily: previewFontFamily,
                mode: viewMode,
                positionSyncID: positionSyncID,
                fileURL: fileURL,
                findState: findState,
                outlineState: outlineState,
                onTaskToggle: { line, checked in
                    toggleTask(line: line, checked: checked)
                },
                onJumpToSource: { line in
                    NotificationCenter.default.post(
                        name: .scrollEditorToLine,
                        object: nil,
                        userInfo: ["line": line]
                    )
                    viewMode = .edit
                },
                contentWidthEm: contentWidthEm
            )
            .opacity(viewMode == .preview ? 1 : 0)
            .allowsHitTesting(viewMode == .preview)
        }
    }

    /// Toggle the `[ ]` / `[x]` on the source line that produced this rendered
    /// task. Called from the preview-side click handler.
    private func toggleTask(line: Int, checked: Bool) {
        let lines = document.text.components(separatedBy: "\n")
        guard line > 0, line <= lines.count else { return }
        let original = lines[line - 1]
        let updated: String
        if checked {
            updated = original.replacingOccurrences(of: "[ ]", with: "[x]", options: [], range: original.range(of: "[ ]"))
        } else {
            updated = original.replacingOccurrences(of: "[x]", with: "[ ]", options: .caseInsensitive, range: original.range(of: "[x]", options: .caseInsensitive))
        }
        guard updated != original else { return }
        var newLines = lines
        newLines[line - 1] = updated
        document.text = newLines.joined(separator: "\n")
    }

    private func exportPDF() {
        PDFExporter().exportPDF(
            markdown: document.text,
            fontSize: CGFloat(fontSize),
            fontFamily: previewFontFamily,
            fileURL: fileURL
        )
    }

    private func printDocument() {
        PDFExporter().printHTML(
            markdown: document.text,
            fontSize: CGFloat(fontSize),
            fontFamily: previewFontFamily,
            fileURL: fileURL
        )
    }
}

// MARK: - Status bar

private struct StatusBar: View {
    @ObservedObject var state: StatusBarState

    var body: some View {
        HStack(spacing: 16) {
            if state.counts.hasSelection {
                Text("\(state.counts.selectionWords) words")
                Text("\(state.counts.selectionChars) chars")
            } else {
                Text("\(state.counts.totalWords) words")
                Text("\(state.counts.totalChars) chars")
                Text(readingTime(seconds: state.counts.totalReadingSeconds))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private func readingTime(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s read" }
        let minutes = (seconds + 30) / 60
        return "\(minutes) min read"
    }
}
