import AppKit
import Combine
import SwiftUI
import WebKit

enum LiveEditorSession {
    static var currentDocumentID: UUID?
}

/// WKWebView subclass that re-focuses CodeMirror when macOS routes
/// first-responder to this view (e.g. after clicking a toolbar button).
final class LiveEditorWebView: WKWebView {
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            evaluateJavaScript("window.clearlyLiveEditor?.focus()")
        }
        return result
    }
}

struct LiveEditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 16
    var fileURL: URL?
    var documentID: UUID?
    var documentEpoch: Int = 0
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

    func makeNSView(context: Context) -> LiveEditorWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalImageSchemeHandler(), forURLScheme: LocalImageSupport.scheme)
        config.userContentController.add(context.coordinator, name: "liveEditor")

        let webView = LiveEditorWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = Theme.backgroundColor
        // Update the session ID before any async callbacks from the old view can race.
        LiveEditorSession.currentDocumentID = documentID
        context.coordinator.attach(webView: webView, findState: findState, outlineState: outlineState)
        loadEditorPage(in: webView)
        return webView
    }

    func updateNSView(_ webView: LiveEditorWebView, context: Context) {
        context.coordinator.parent = self
        webView.underPageBackgroundColor = Theme.backgroundColor
        LiveEditorSession.currentDocumentID = documentID
        context.coordinator.attach(webView: webView, findState: findState, outlineState: outlineState)
        context.coordinator.syncFromSwiftIfNeeded()
    }

    static func dismantleNSView(_ webView: LiveEditorWebView, coordinator: Coordinator) {
        // Mark the coordinator as dismantled first so any in-flight async callbacks
        // (evaluateJavaScript completions, WKScriptMessage deliveries) are ignored.
        coordinator.isDismantled = true
        coordinator.removePasteMonitor()
        NotificationCenter.default.removeObserver(coordinator)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "liveEditor")
    }

    private func loadEditorPage(in webView: WKWebView) {
        guard let indexURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "live-editor"),
              let resourceURL = Bundle.main.resourceURL else {
            webView.loadHTMLString(
                """
                <html>
                <body style="font-family: -apple-system; padding: 24px;">
                <h3>Live Preview failed to load</h3>
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
        var parent: LiveEditorView
        /// Set in `dismantleNSView` to prevent stale async callbacks from writing
        /// to the binding after this coordinator's view has been removed.
        var isDismantled = false

        private weak var webView: WKWebView?
        private var hasRegisteredObservers = false
        private var isReady = false
        private var lastSyncedText = ""
        /// True once the coordinator has received at least one `docChanged` from JS.
        /// Distinguishes "editor content is genuinely empty" (true, lastSyncedText=="")
        /// from "no docChanged has arrived yet" (false) so the synchronous flush
        /// path can safely deliver an empty string without incorrectly skipping it.
        private var hasReceivedDocChanged = false
        private var lastKnownDocumentID: UUID?
        private var lastThemeSignature = ""
        private var findCancellables = Set<AnyCancellable>()
        /// Local event monitor that intercepts Cmd+V and routes it through
        /// NSPasteboard → CodeMirror's dispatch API, bypassing WKWebView's native
        /// paste which either (a) doesn't reach our view when another view is
        /// first-responder or (b) delivers empty clipboard data in file:// contexts.
        private var pasteEventMonitor: Any?

        init(parent: LiveEditorView) {
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
            self.parent.findState?.activeMode = .edit

            if !hasRegisteredObservers {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleFormattingCommand(_:)),
                    name: .liveEditorCommand,
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

                // Register a local event monitor to intercept Cmd+V before the
                // responder chain sees it. This is required because:
                //   1. WKWebContentView (private) is the actual first-responder,
                //      so our performKeyEquivalent override on LiveEditorWebView
                //      is never reached for Cmd+V.
                //   2. Even when WKWebView fires a DOM paste event, ClipboardEvent
                //      .clipboardData is empty in file:// contexts (WebKit security).
                // Solution: intercept at the NSEvent level, read from NSPasteboard
                // (full access), and inject via CodeMirror's dispatch API.
                pasteEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self,
                          !self.isDismantled,
                          self.isReady,
                          event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                          event.charactersIgnoringModifiers == "v",
                          let webView = self.webView,
                          webView.window?.isKeyWindow == true,
                          let text = NSPasteboard.general.string(forType: .string) else {
                        return event
                    }
                    // Only redirect paste into the editor when the webview (or one
                    // of its private subviews like WKWebContentView) is the actual
                    // first responder. Any other control — sidebar, find bar, etc. —
                    // gets native paste unchanged.
                    guard let fr = webView.window?.firstResponder as? NSView,
                          fr.isDescendant(of: webView) else {
                        return event
                    }
                    self.insertText(text)
                    return nil  // Consume — prevents WKWebView's broken native paste
                }
            }

            if let findState {
                observeFindState(findState)
                findState.editorNavigateToNext = { [weak self] in
                    self?.call(function: "applyCommand", payload: ["command": "findNext"])
                }
                findState.editorNavigateToPrevious = { [weak self] in
                    self?.call(function: "applyCommand", payload: ["command": "findPrevious"])
                }
            }

            outlineState?.scrollToRange = { [weak self] range in
                self?.scrollToOffset(range.location)
            }
        }

        func syncFromSwiftIfNeeded() {
            parent.findState?.activeMode = .edit
            guard isReady else { return }

            // Detect document switches (updateNSView fired with a new documentID).
            // Reset hasReceivedDocChanged so the synchronous flush path cannot deliver
            // the previous document's lastSyncedText before the first docChanged from
            // the new document arrives.
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

            if parent.text != lastSyncedText {
                lastSyncedText = parent.text
                call(function: "setDocument", payload: ["markdown": parent.text, "epoch": parent.documentEpoch])
            }

            if parent.findState?.isVisible == true {
                call(function: "setFindQuery", payload: ["query": parent.findState?.query ?? ""])
            } else {
                call(function: "setFindQuery", payload: ["query": ""])
            }
        }

        func observeFindState(_ state: FindState) {
            findCancellables.removeAll()

            state.$query
                .removeDuplicates()
                .sink { [weak self] query in
                    guard let self,
                          state.isVisible,
                          state.activeMode == .edit else { return }
                    self.call(function: "setFindQuery", payload: ["query": query])
                }
                .store(in: &findCancellables)

            state.$isVisible
                .removeDuplicates()
                .sink { [weak self] visible in
                    guard let self else { return }
                    let query = visible && state.activeMode == .edit ? state.query : ""
                    self.call(function: "setFindQuery", payload: ["query": query])
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

            // Synchronously deliver the last confirmed JS content so that any
            // snapshot (save/switch) that triggered this flush reads a current
            // value from currentFileText before returning. lastSyncedText is
            // updated on every docChanged and is the best synchronous approximation
            // of what the JS engine holds. The async getDocument() below is a safety
            // net for the rare gap between the last docChanged delivery and now.
            //
            // Guard on hasReceivedDocChanged, not lastSyncedText.isEmpty: an empty
            // string is a valid confirmed state (user deleted all content) and must
            // be flushed. Only skip when no docChanged has arrived yet (initial state
            // where lastSyncedText=="" means "uninitialized", not "empty document").
            // Also guard against the window between a document switch
            // (WorkspaceManager updated LiveEditorSession.currentDocumentID) and
            // the next SwiftUI updateNSView (which updates parent.documentID).
            // If they don't match, the coordinator's parent is stale and
            // lastSyncedText belongs to the previous document.
            if hasReceivedDocChanged,
               parent.documentID == LiveEditorSession.currentDocumentID {
                parent.onFlushContent?(lastSyncedText)
            }

            // Async JS round-trip: captures any keystrokes still in-flight that
            // haven't yet fired a docChanged WKScriptMessage.
            // Capture both document identity AND host revision so the completion
            // is rejected if either a document switch or a same-document host
            // replacement (external file change, discard) has occurred since the
            // flush started — matching the same guard pattern used in docChanged.
            let requestedDocumentID = parent.documentID
            let requestedEpoch = parent.documentEpoch
            webView.evaluateJavaScript("window.clearlyLiveEditor && window.clearlyLiveEditor.getDocument && window.clearlyLiveEditor.getDocument()") { [weak self] result, _ in
                guard let self,
                      !self.isDismantled,
                      requestedDocumentID == LiveEditorSession.currentDocumentID,
                      requestedEpoch == self.parent.documentEpoch,
                      let markdown = result as? String else { return }
                self.lastSyncedText = markdown
                if Thread.isMainThread {
                    self.parent.text = markdown
                } else {
                    DispatchQueue.main.async {
                        self.parent.text = markdown
                    }
                }
            }
        }

        private func insertText(_ text: String) {
            call(function: "insertText", payload: ["text": text])
        }

        private func scrollToOffset(_ offset: Int) {
            call(function: "scrollToOffset", payload: ["offset": offset])
        }

        private func mountEditor() {
            // Reset lastSyncedText to "" so syncFromSwiftIfNeeded always calls
            // setDocument after mount. This is a defensive measure: if mount
            // initialised CodeMirror with incorrect content (e.g. due to a timing
            // edge-case), setDocument corrects it. If the content already matches,
            // the JS setDocument is a no-op.
            lastSyncedText = ""
            hasReceivedDocChanged = false
            lastThemeSignature = ""
            call(
                function: "mount",
                payload: [
                    "markdown": parent.text,
                    "appearance": parent.colorScheme == .dark ? "dark" : "light",
                    "fontSize": Double(parent.fontSize),
                    "filePath": parent.fileURL?.path ?? "",
                    "epoch": parent.documentEpoch
                ]
            )
            syncFromSwiftIfNeeded()
            call(function: "focus")
            // Make the WKWebView the NSView first responder so that keyboard
            // events — including Cmd+V paste — reach the web content without
            // requiring the user to click the editor first.
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.isDismantled, let webView = self.webView else { return }
                webView.window?.makeFirstResponder(webView)
            }
        }

        private func handleBridgeMessage(_ body: [String: Any]) {
            guard let type = body["type"] as? String else { return }

            switch type {
            case "ready":
                isReady = true
                mountEditor()

            case "docChanged":
                guard !isDismantled,
                      parent.documentID == LiveEditorSession.currentDocumentID,
                      let epochNumber = body["epoch"] as? NSNumber,
                      epochNumber.intValue == parent.documentEpoch,
                      let markdown = body["markdown"] as? String else { return }
                hasReceivedDocChanged = true
                lastSyncedText = markdown
                if Thread.isMainThread {
                    self.parent.text = markdown
                } else {
                    DispatchQueue.main.async {
                        self.parent.text = markdown
                    }
                }

            case "findStatus":
                guard parent.documentID == LiveEditorSession.currentDocumentID,
                      let matchCount = body["matchCount"] as? Int,
                      let currentIndex = body["currentIndex"] as? Int else { return }
                DispatchQueue.main.async {
                    guard self.parent.findState?.activeMode == .edit || self.parent.findState?.isVisible == false else { return }
                    self.parent.findState?.matchCount = matchCount
                    self.parent.findState?.currentIndex = currentIndex
                }

            case "openLink":
                guard parent.documentID == LiveEditorSession.currentDocumentID else { return }
                let kind = body["kind"] as? String ?? "markdown"
                switch kind {
                case "wiki":
                    guard let target = body["target"] as? String else { return }
                    let heading = body["heading"] as? String
                    DispatchQueue.main.async {
                        self.parent.onWikiLinkClicked?(target, heading)
                    }
                case "tag":
                    guard let tag = body["tag"] as? String else { return }
                    DispatchQueue.main.async {
                        self.parent.onTagClicked?(tag)
                    }
                default:
                    guard let href = body["href"] as? String else { return }
                    DispatchQueue.main.async {
                        self.parent.onMarkdownLinkClicked?(href)
                    }
                }

            case "log":
                if let message = body["message"] as? String {
                    DiagnosticLog.log("LiveEditor: \(message)")
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
                script = "window.clearlyLiveEditor && window.clearlyLiveEditor.\(function)(\(json));"
            } else {
                script = "window.clearlyLiveEditor && window.clearlyLiveEditor.\(function)();"
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
            DiagnosticLog.log("LiveEditorView: web content loaded")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DiagnosticLog.log("LiveEditorView navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            DiagnosticLog.log("LiveEditorView provisional navigation failed: \(error.localizedDescription)")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "liveEditor",
                  let body = message.body as? [String: Any] else { return }
            handleBridgeMessage(body)
        }
    }
}
