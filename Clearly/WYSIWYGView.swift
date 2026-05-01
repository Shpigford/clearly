import AppKit
import Combine
import SwiftUI
import WebKit
import ClearlyCore

/// Tiptap-based WYSIWYG editor hosted inside a WKWebView. Mirrors the shape
/// of `LiveEditorView` (CodeMirror live preview) but talks to the Tiptap
/// bundle at `Shared/Resources/wysiwyg/wysiwyg.js`. Phase 2 scope: mount,
/// bidirectional doc sync, theme, basic formatting commands. Paste, find,
/// and persisted folds land in later phases.

/// WKWebView subclass that:
/// 1. Re-focuses Tiptap when macOS routes first-responder to this view.
/// 2. Intercepts file-URL drops at the AppKit level so dropped images get
///    written as a sibling file via ImagePasteService and inserted as
///    markdown rather than embedded as `file://` absolute references.
final class WYSIWYGWebView: WKWebView {
    /// Set by the coordinator. Returns the currently-open document URL so
    /// dropped image data can be written next to it.
    var documentURLProvider: (() -> URL?)?
    /// Set by the coordinator. Inserts the resulting markdown into the
    /// editor at the current selection (e.g. `![alt](path/to/img.png)`).
    var insertTextHandler: ((String) -> Void)?

    private static let acceptedDragTypes: [NSPasteboard.PasteboardType] = [.fileURL]
    private static let acceptedFileExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "tiff"]

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        registerForDraggedTypes(Self.acceptedDragTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not used")
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            evaluateJavaScript("window.clearlyWYSIWYG?.focus()")
        }
        return result
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if let urls = imageURLs(in: sender), !urls.isEmpty {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if let urls = imageURLs(in: sender), !urls.isEmpty {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = imageURLs(in: sender), !urls.isEmpty else {
            return super.performDragOperation(sender)
        }
        guard let docURL = documentURLProvider?() else {
            // No open document — fall back to default.
            return super.performDragOperation(sender)
        }
        var inserted = 0
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let ext = (url.pathExtension.isEmpty ? "png" : url.pathExtension).lowercased()
            do {
                let result = try ImagePasteService.writeImageData(data, ext: ext, besidesDocumentAt: docURL, presenter: nil)
                insertTextHandler?(result.markdown)
                if inserted < urls.count - 1 {
                    insertTextHandler?("\n\n")
                }
                inserted += 1
            } catch {
                DiagnosticLog.log("WYSIWYG drop: writeImageData failed: \(error.localizedDescription)")
            }
        }
        return inserted > 0
    }

    private func imageURLs(in sender: any NSDraggingInfo) -> [URL]? {
        let pasteboard = sender.draggingPasteboard
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] else {
            return nil
        }
        let images = urls.filter { Self.acceptedFileExtensions.contains($0.pathExtension.lowercased()) }
        return images.isEmpty ? nil : images
    }
}

/// Lightweight payload for the Tiptap wiki-link autocomplete popup. Each
/// vault file is published as a `{title, path}` pair; the JS side filters
/// these locally so typing inside the `[[…]]` popup is instant.
struct WYSIWYGWikiTarget: Equatable {
    let title: String
    let path: String
}

/// Lightweight payload for the Tiptap tag autocomplete popup.
struct WYSIWYGTagTarget: Equatable {
    let name: String
    let count: Int
}

struct WYSIWYGView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 16
    var fileURL: URL?
    var documentID: UUID?
    var documentEpoch: Int = 0
    var wikiTargets: [WYSIWYGWikiTarget] = []
    var tagTargets: [WYSIWYGTagTarget] = []
    var contentWidthEm: CGFloat?
    var findState: FindState?
    var outlineState: OutlineState?
    var onMarkdownLinkClicked: ((String) -> Void)?
    var onWikiLinkClicked: ((String, String?) -> Void)?
    var onTagClicked: ((String) -> Void)?
    /// Called synchronously during a flush to deliver the last confirmed editor
    /// content before any snapshot (save/switch) reads `currentFileText`.
    var onFlushContent: ((String) -> Void)?
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WYSIWYGWebView {
        DiagnosticLog.log("WYSIWYGView.makeNSView: \(text.count) chars")
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "wysiwyg")

        let webView = WYSIWYGWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = Theme.backgroundColor
        WYSIWYGSession.update(documentID: documentID, epoch: documentEpoch)
        context.coordinator.attach(webView: webView, findState: findState, outlineState: outlineState)
        loadEditorPage(in: webView)
        return webView
    }

    func updateNSView(_ webView: WYSIWYGWebView, context: Context) {
        DiagnosticLog.log("WYSIWYGView.updateNSView: \(text.count) chars")
        context.coordinator.parent = self
        webView.underPageBackgroundColor = Theme.backgroundColor
        WYSIWYGSession.update(documentID: documentID, epoch: documentEpoch)
        context.coordinator.attach(webView: webView, findState: findState, outlineState: outlineState)
        context.coordinator.syncFromSwiftIfNeeded()
    }

    static func dismantleNSView(_ webView: WYSIWYGWebView, coordinator: Coordinator) {
        coordinator.isDismantled = true
        coordinator.removePasteMonitor()
        NotificationCenter.default.removeObserver(coordinator)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "wysiwyg")
    }

    private func loadEditorPage(in webView: WKWebView) {
        guard let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "wysiwyg"),
              let resourceURL = Bundle.main.resourceURL else {
            webView.loadHTMLString(
                """
                <html>
                <body style="font-family: -apple-system; padding: 24px;">
                <h3>WYSIWYG editor failed to load</h3>
                <p>The bundled web editor assets were not found in the app resources.</p>
                </body>
                </html>
                """,
                baseURL: nil
            )
            return
        }
        webView.loadFileURL(indexURL, allowingReadAccessTo: resourceURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WYSIWYGView
        var isDismantled = false

        private weak var webView: WKWebView?
        private var hasRegisteredObservers = false
        private var isReady = false
        private var lastSyncedText = ""
        private var hasReceivedDocChanged = false
        private var lastKnownDocumentID: UUID?
        private var lastThemeSignature = ""
        private weak var observedFindState: FindState?
        private var lastFindSignature = ""
        private var lastFindVisibility = false
        private var findCancellables = Set<AnyCancellable>()
        private var lastWikiTargetsHash: Int = 0
        private var lastTagTargetsHash: Int = 0
        private var lastContentWidthCSS: String = ""
        /// Local event monitor that intercepts Cmd+V before the responder chain
        /// sees it. Required because WKWebView's DOM `paste` event delivers
        /// empty clipboardData in file:// contexts (WebKit security), and our
        /// outer WKWebView.becomeFirstResponder override doesn't see Cmd+V
        /// directly — WKWebContentView (private) is the actual first-responder.
        private var pasteEventMonitor: Any?

        init(parent: WYSIWYGView) {
            self.parent = parent
        }

        deinit {
            removePasteMonitor()
        }

        func removePasteMonitor() {
            if let monitor = pasteEventMonitor {
                NSEvent.removeMonitor(monitor)
                pasteEventMonitor = nil
            }
        }

        func attach(webView: WKWebView, findState: FindState?, outlineState: OutlineState?) {
            self.webView = webView
            self.parent.findState?.activeMode = .wysiwyg

            // Wire drop-handling callbacks each time `attach` runs so the
            // closures always reach the current `parent` (which may have
            // mutated after a doc switch).
            if let typedView = webView as? WYSIWYGWebView {
                typedView.documentURLProvider = { [weak self] in
                    self?.parent.fileURL
                }
                typedView.insertTextHandler = { [weak self] text in
                    self?.insertText(text)
                }
            }

            // Outline → editor scroll: find the Nth heading in the PM tree
            // and scroll into view. We use the heading's index in
            // `outlineState.headings` rather than a byte offset because PM
            // positions don't map cleanly back to source markdown bytes.
            outlineState?.scrollToRange = { [weak self, weak outlineState] range in
                guard let self,
                      let headings = outlineState?.headings else { return }
                guard let ordinal = headings.firstIndex(where: { $0.range == range }) else { return }
                self.call(function: "scrollToHeading", payload: ["ordinal": ordinal])
            }

            if let findState, observedFindState !== findState {
                observedFindState = findState
                observeFindState(findState)
                findState.editorNavigateToNext = { [weak self] in
                    self?.call(function: "applyCommand", payload: ["command": "findNext"])
                }
                findState.editorNavigateToPrevious = { [weak self] in
                    self?.call(function: "applyCommand", payload: ["command": "findPrevious"])
                }
                findState.editorPerformReplace = { [weak self, weak findState] in
                    guard let self, let findState else { return }
                    self.syncFindState(findState, force: true)
                    self.call(function: "applyCommand", payload: ["command": "replaceCurrent"])
                }
                findState.editorPerformReplaceAll = { [weak self, weak findState] in
                    guard let self, let findState else { return }
                    self.syncFindState(findState, force: true)
                    self.call(function: "applyCommand", payload: ["command": "replaceAll"])
                }
            }

            if !hasRegisteredObservers {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleFormattingCommand(_:)),
                    name: .wysiwygCommand,
                    object: nil
                )
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleScrollToLine(_:)),
                    name: .scrollEditorToLine,
                    object: nil
                )
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(flushEditorBuffer(_:)),
                    name: .flushEditorBuffer,
                    object: nil
                )
                hasRegisteredObservers = true

                pasteEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self,
                          !self.isDismantled,
                          self.isReady,
                          self.parent.findState?.isVisible != true,
                          event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                          event.charactersIgnoringModifiers == "v",
                          let webView = self.webView,
                          webView.window?.isKeyWindow == true else {
                        return event
                    }
                    // Only redirect paste when WKWebContentView (or its
                    // descendants) is the actual first responder. Sidebar,
                    // find bar, etc. get native paste unchanged.
                    guard let fr = webView.window?.firstResponder as? NSView,
                          fr.isDescendant(of: webView) else {
                        return event
                    }
                    let pasteboard = NSPasteboard.general
                    if self.tryInsertImageFromPasteboard(pasteboard) != nil {
                        return nil  // Consume — image was written + markdown inserted
                    }
                    if let text = pasteboard.string(forType: .string) {
                        self.insertText(text)
                        return nil
                    }
                    return event
                }
            }
        }

        private func insertText(_ text: String) {
            call(function: "insertText", payload: ["text": text])
        }

        /// Reads an image from the pasteboard, writes it as a sibling file
        /// next to the open document, and inserts a markdown image token via
        /// the JS bridge. Returns the markdown token on success, nil when
        /// there's no usable image or no document URL. Mirrors LiveEditorView.
        fileprivate func tryInsertImageFromPasteboard(_ pasteboard: NSPasteboard) -> String? {
            guard let docURL = parent.fileURL else { return nil }

            // Preserve-format types: write original bytes with matching ext
            // so animations / quality / metadata survive. JPEG / GIF / HEIC
            // don't have built-in NSPasteboard.PasteboardType constants.
            let preserveFormats: [(NSPasteboard.PasteboardType, String)] = [
                (.png, "png"),
                (NSPasteboard.PasteboardType("public.jpeg"), "jpg"),
                (NSPasteboard.PasteboardType("com.compuserve.gif"), "gif"),
                (NSPasteboard.PasteboardType("public.heic"), "heic"),
            ]
            var pickedData: Data?
            var pickedExt: String?
            for (type, ext) in preserveFormats {
                if let data = pasteboard.data(forType: type) {
                    pickedData = data
                    pickedExt = ext
                    break
                }
            }
            // TIFF is macOS's generic image container — Cmd+Shift+Ctrl+4
            // screenshots land here. Decode + re-encode to PNG so we don't
            // drop a multi-MB uncompressed sibling next to the document.
            if pickedData == nil,
               let tiff = pasteboard.data(forType: .tiff),
               let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                pickedData = png
                pickedExt = "png"
            }
            guard let data = pickedData, let ext = pickedExt else { return nil }

            do {
                let result = try ImagePasteService.writeImageData(data, ext: ext, besidesDocumentAt: docURL, presenter: nil)
                self.insertText(result.markdown)
                return result.markdown
            } catch {
                DiagnosticLog.log("WYSIWYG paste: writeImageData failed: \(error.localizedDescription)")
                return nil
            }
        }

        func syncFromSwiftIfNeeded() {
            parent.findState?.activeMode = .wysiwyg
            guard isReady else { return }

            // Detect document switches so the synchronous flush path doesn't
            // deliver the previous document's lastSyncedText before the first
            // docChanged from the new document arrives.
            if parent.documentID != lastKnownDocumentID {
                lastKnownDocumentID = parent.documentID
                hasReceivedDocChanged = false
            }

            let appearance = parent.colorScheme == .dark ? "dark" : "light"
            let themeSignature = "\(appearance)|\(parent.fontSize)|\(parent.fileURL?.path ?? "")"
            if themeSignature != lastThemeSignature {
                lastThemeSignature = themeSignature
                call(
                    function: "setTheme",
                    payload: [
                        "appearance": appearance,
                        "fontSize": Double(parent.fontSize),
                        "filePath": parent.fileURL?.path ?? ""
                    ]
                )
            }

            applyContentWidthIfNeeded()

            if parent.text != lastSyncedText {
                lastSyncedText = parent.text
                call(function: "setDocument", payload: ["markdown": parent.text, "epoch": parent.documentEpoch])
            }

            let wikiHash = parent.wikiTargets.reduce(0) { $0 ^ $1.title.hashValue ^ $1.path.hashValue }
            if wikiHash != lastWikiTargetsHash {
                lastWikiTargetsHash = wikiHash
                let payload: [[String: Any]] = parent.wikiTargets.map { ["title": $0.title, "path": $0.path] }
                call(function: "setWikiTargets", payload: ["targets": payload])
            }

            let tagHash = parent.tagTargets.reduce(0) { $0 ^ $1.name.hashValue &+ $1.count }
            if tagHash != lastTagTargetsHash {
                lastTagTargetsHash = tagHash
                let payload: [[String: Any]] = parent.tagTargets.map { ["name": $0.name, "count": $0.count] }
                call(function: "setTagTargets", payload: ["targets": payload])
            }

            if parent.findState?.isVisible == true {
                if let findState = parent.findState {
                    if !lastFindVisibility {
                        lastFindVisibility = true
                    }
                    syncFindState(findState)
                }
            } else {
                if lastFindVisibility || !lastFindSignature.isEmpty {
                    lastFindSignature = ""
                    lastFindVisibility = false
                    call(function: "setFindQuery", payload: [
                        "query": "",
                        "replacement": "",
                        "caseSensitive": false,
                        "wholeWord": false,
                        "regex": false,
                    ])
                }
            }
        }

        /// Pushes the user's Content Width preference into the editor page as
        /// a CSS variable. The default 760px (defined in `index.html`) is
        /// restored when the setting is "off". Body padding inside `#editor`
        /// is 28px on each side, so we add 56px to the em value to keep the
        /// text-wrap width matching the user's chosen em count.
        private func applyContentWidthIfNeeded() {
            let value: String
            if let em = parent.contentWidthEm {
                value = "calc(\(Int(em))em + 56px)"
            } else {
                value = "760px"
            }
            guard value != lastContentWidthCSS else { return }
            lastContentWidthCSS = value
            guard let webView else { return }
            let escaped = value.replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript(
                "document.documentElement.style.setProperty('--editor-max-width', '\(escaped)');"
            )
        }

        private func syncFindState(_ state: FindState, force: Bool = false) {
            let query = state.isVisible && state.activeMode == .wysiwyg ? state.query : ""
            let signature = [
                query,
                state.replacementText,
                state.caseSensitive ? "1" : "0",
                state.useRegex ? "1" : "0"
            ].joined(separator: "\u{1f}")
            guard force || signature != lastFindSignature else { return }
            lastFindSignature = signature
            call(function: "setFindQuery", payload: [
                "query": query,
                "replacement": state.replacementText,
                "caseSensitive": state.caseSensitive,
                "wholeWord": false,
                "regex": state.useRegex
            ])
        }

        private func observeFindState(_ state: FindState) {
            findCancellables.removeAll()

            state.$query
                .removeDuplicates()
                .sink { [weak self, weak state] _ in
                    DispatchQueue.main.async {
                        guard let self, let state, state.isVisible, state.activeMode == .wysiwyg else { return }
                        self.syncFindState(state)
                    }
                }
                .store(in: &findCancellables)

            state.$isVisible
                .removeDuplicates()
                .sink { [weak self, weak state] visible in
                    DispatchQueue.main.async {
                        guard let self, let state else { return }
                        self.lastFindVisibility = visible
                        self.syncFindState(state, force: true)
                    }
                }
                .store(in: &findCancellables)

            Publishers.CombineLatest(state.$caseSensitive, state.$useRegex)
                .dropFirst()
                .sink { [weak self, weak state] _, _ in
                    DispatchQueue.main.async {
                        guard let self, let state, state.isVisible, state.activeMode == .wysiwyg else { return }
                        self.syncFindState(state)
                    }
                }
                .store(in: &findCancellables)

            state.$replacementText
                .removeDuplicates()
                .sink { [weak self, weak state] _ in
                    DispatchQueue.main.async {
                        guard let self, let state, state.isVisible, state.activeMode == .wysiwyg else { return }
                        self.syncFindState(state)
                    }
                }
                .store(in: &findCancellables)
        }

        @objc func handleFormattingCommand(_ notification: Notification) {
            guard let rawValue = notification.userInfo?["command"] as? String else { return }
            call(function: "applyCommand", payload: ["command": rawValue])
        }

        @objc func handleScrollToLine(_ notification: Notification) {
            guard let line = notification.userInfo?["line"] as? Int, line > 0 else { return }
            call(function: "scrollToLine", payload: ["line": line])
        }

        @objc func flushEditorBuffer(_ notification: Notification) {
            guard !isDismantled, isReady, let webView else { return }

            // Synchronous best-effort: deliver lastSyncedText so the snapshot
            // path reads a current value. Mirrors the LiveEditorView pattern.
            if hasReceivedDocChanged,
               WYSIWYGSession.matches(documentID: parent.documentID) {
                parent.onFlushContent?(lastSyncedText)
            }

            let requestedDocumentID = parent.documentID
            let requestedEpoch = parent.documentEpoch
            webView.evaluateJavaScript("window.clearlyWYSIWYG && window.clearlyWYSIWYG.getDocument && window.clearlyWYSIWYG.getDocument()") { [weak self] result, _ in
                guard let self,
                      !self.isDismantled,
                      WYSIWYGSession.matches(documentID: requestedDocumentID, epoch: requestedEpoch),
                      requestedEpoch == self.parent.documentEpoch,
                      let markdown = result as? String else { return }
                self.applyEditorMarkdown(markdown, markDirty: true)
            }
        }

        private func applyEditorMarkdown(_ markdown: String, markDirty: Bool) {
            lastSyncedText = markdown

            let apply = { [weak self] in
                guard let self, !self.isDismantled else { return }
                self.parent.text = markdown
                if markDirty {
                    WorkspaceManager.shared.contentDidChange()
                }
            }

            if Thread.isMainThread {
                apply()
            } else {
                DispatchQueue.main.async(execute: apply)
            }
        }

        private func mountEditor() {
            DiagnosticLog.log("WYSIWYGView: mounting editor (\(parent.text.count) chars)")
            lastSyncedText = ""
            hasReceivedDocChanged = false
            lastThemeSignature = ""
            call(
                function: "mount",
                payload: [
                    "appearance": parent.colorScheme == .dark ? "dark" : "light",
                    "fontSize": Double(parent.fontSize),
                    "filePath": parent.fileURL?.path ?? "",
                    "epoch": parent.documentEpoch
                ]
            )
            // Push the markdown after mount — the bundle's mount() initializes
            // an empty editor; setDocument replaces with the real content.
            syncFromSwiftIfNeeded()
            call(function: "focus")
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isDismantled, let webView = self.webView else { return }
                webView.window?.makeFirstResponder(webView)
            }
        }

        private func handleBridgeMessage(_ body: [String: Any]) {
            guard let type = body["type"] as? String else { return }

            switch type {
            case "ready":
                DiagnosticLog.log("WYSIWYGView: received ready from web content")
                isReady = true
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isDismantled else { return }
                    self.mountEditor()
                }

            case "docChanged":
                guard !isDismantled,
                      WYSIWYGSession.matches(documentID: parent.documentID),
                      let epochNumber = body["epoch"] as? NSNumber,
                      epochNumber.intValue == parent.documentEpoch,
                      let markdown = body["markdown"] as? String else { return }
                hasReceivedDocChanged = true
                applyEditorMarkdown(markdown, markDirty: true)

            case "findStatus":
                guard WYSIWYGSession.matches(documentID: parent.documentID),
                      let matchCount = body["matchCount"] as? Int,
                      let currentIndex = body["currentIndex"] as? Int else { return }
                let regexError = body["regexError"] as? String
                DispatchQueue.main.async {
                    guard self.parent.findState?.activeMode == .wysiwyg else { return }
                    self.parent.findState?.matchCount = matchCount
                    self.parent.findState?.currentIndex = currentIndex
                    self.parent.findState?.resultsAreStale = false
                    self.parent.findState?.regexError = regexError
                    self.parent.findState?.lastReplaceCount = nil
                }

            case "replaceStatus":
                guard WYSIWYGSession.matches(documentID: parent.documentID),
                      let replaceCount = body["replaceCount"] as? Int else { return }
                DispatchQueue.main.async {
                    guard self.parent.findState?.activeMode == .wysiwyg else { return }
                    self.parent.findState?.lastReplaceCount = replaceCount
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                    guard let self, self.parent.findState?.lastReplaceCount == replaceCount else { return }
                    self.parent.findState?.lastReplaceCount = nil
                }

            case "openLink":
                guard WYSIWYGSession.matches(documentID: parent.documentID) else { return }
                let kind = body["kind"] as? String ?? "url"
                switch kind {
                case "wiki":
                    guard let target = body["target"] as? String else { return }
                    let heading = body["heading"] as? String
                    DispatchQueue.main.async {
                        self.parent.onWikiLinkClicked?(target, heading)
                    }
                case "tag":
                    guard let tag = body["target"] as? String ?? body["tag"] as? String else { return }
                    DispatchQueue.main.async {
                        self.parent.onTagClicked?(tag)
                    }
                default:
                    guard let href = body["target"] as? String ?? body["href"] as? String else { return }
                    DispatchQueue.main.async {
                        self.parent.onMarkdownLinkClicked?(href)
                    }
                }

            case "log":
                if let line = body["line"] as? String {
                    DiagnosticLog.log("WYSIWYG: \(line)")
                }

            default:
                break
            }
        }

        private func call(function: String, payload: [String: Any]? = nil) {
            guard let webView else { return }

            let script: String
            if let payload {
                guard let json = serializeJSONObject(payload) else { return }
                script = "window.clearlyWYSIWYG && window.clearlyWYSIWYG.\(function)(\(json));"
            } else {
                script = "window.clearlyWYSIWYG && window.clearlyWYSIWYG.\(function)();"
            }
            webView.evaluateJavaScript(script)
        }

        private func serializeJSONObject(_ object: [String: Any]) -> String? {
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object),
                  let json = String(data: data, encoding: .utf8) else {
                return nil
            }
            return json
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DiagnosticLog.log("WYSIWYGView: web content loaded")
            guard !isReady else { return }
            DiagnosticLog.log("WYSIWYGView: didFinish fallback mount")
            isReady = true
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isDismantled else { return }
                self.mountEditor()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DiagnosticLog.log("WYSIWYGView navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DiagnosticLog.log("WYSIWYGView provisional navigation failed: \(error.localizedDescription)")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "wysiwyg",
                  let body = message.body as? [String: Any] else { return }
            handleBridgeMessage(body)
        }
    }
}
