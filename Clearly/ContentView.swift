import SwiftUI
import AppKit
import ClearlyCore

/// Per-document scene root: hosts the editor / preview, find bar, jump-to-line
/// bar, outline panel, and the floating bottom toolbar (mode picker / counts /
/// copy / outline). One instance per `DocumentGroup` window.
struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @State private var viewMode: ViewMode
    @StateObject private var outlineState = OutlineState()
    @StateObject private var findState = FindState()
    @StateObject private var jumpToLineState = JumpToLineState()
    @StateObject private var statusBarState = StatusBarState()

    @AppStorage("editorFontSize") private var fontSize: Double = 12
    @AppStorage("previewFontFamily") private var previewFontFamily: String = "sanFrancisco"
    @AppStorage("contentWidth") private var contentWidth: String = "off"
    @AppStorage("showLineNumbers") private var showLineNumbers: Bool = false
    @AppStorage("alwaysShowBottomToolbar") private var alwaysShowBottomToolbar: Bool = false

    @State private var isHoveringBottom: Bool = false

    /// Stable per-window key for ScrollBridge / SelectionBridge. Re-keyed on
    /// document URL change so two windows on different files don't collide.
    @State private var positionSyncID: String = UUID().uuidString

    init(document: Binding<MarkdownDocument>, fileURL: URL?) {
        self._document = document
        self.fileURL = fileURL
        // Never land a blank document in Preview — there'd be nothing to see
        // and no obvious way to edit.
        let raw = UserDefaults.standard.string(forKey: "defaultViewMode") ?? "edit"
        let preferred = ViewMode(rawValue: raw) ?? .edit
        let isBlank = document.wrappedValue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self._viewMode = State(initialValue: (preferred == .preview && isBlank) ? .edit : preferred)
    }

    private var shouldShowBottomToolbar: Bool {
        alwaysShowBottomToolbar || isHoveringBottom
    }

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
                    .overlay(alignment: .bottom) {
                        ZStack(alignment: .bottom) {
                            BottomHoverTracker { hovering in
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    isHoveringBottom = hovering
                                }
                            }
                            .frame(height: 96)

                            if shouldShowBottomToolbar {
                                LinearGradient(
                                    stops: [
                                        .init(color: Theme.backgroundColorSwiftUI.opacity(0), location: 0),
                                        .init(color: Theme.backgroundColorSwiftUI.opacity(0.7), location: 0.55),
                                        .init(color: Theme.backgroundColorSwiftUI, location: 1)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 96)
                                .allowsHitTesting(false)
                                .transition(.opacity)

                                BottomToolbar(
                                    viewMode: $viewMode,
                                    statusBarState: statusBarState,
                                    outlineState: outlineState,
                                    fileURL: fileURL,
                                    documentText: { document.text }
                                )
                                .padding(.horizontal, 12)
                                .padding(.bottom, 6)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                    }

                if outlineState.isVisible {
                    OutlineView(outlineState: outlineState, isEditorVisible: viewMode == .edit)
                        .frame(width: 240)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 360)
        .focusedSceneValue(\.findState, findState)
        .focusedSceneValue(\.outlineState, outlineState)
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
        .watchExternalChanges(fileURL: fileURL, text: $document.text) { url in
            // Sync SwiftUI's underlying NSDocument's fileModificationDate to
            // the new on-disk mtime — without this, the next autosave detects
            // a conflict and shows "could not be autosaved" dialog. We
            // deliberately do NOT try to suppress the title's "Edited"
            // decoration: SwiftUI tracks its own FileDocument-vs-disk diff
            // for that, and the indicator is a useful "doc changed under you"
            // signal anyway.
            let target = url.standardizedFileURL
            guard let doc = NSDocumentController.shared.documents.first(where: { $0.fileURL?.standardizedFileURL == target }) else { return }
            if let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date {
                doc.fileModificationDate = mtime
            }
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
                extraBottomInset: BottomToolbar.pillHeight + 24,
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

