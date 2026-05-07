import Cocoa
import ClearlyCore
import QuickLookUI
import WebKit

class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private var webView: WKWebView!
    private var previewTask: Task<Void, Never>?
    // QuickLook treats the handler as "preview ready"; only call it once the
    // WebView has actually finished loading the rendered HTML.
    private var pendingCompletion: ((Error?) -> Void)?

    deinit {
        previewTask?.cancel()
    }

    override func loadView() {
        webView = WKWebView()
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        self.view = container
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        previewTask?.cancel()
        // Resolve any prior pending handler so QuickLook isn't left waiting.
        if let prior = pendingCompletion {
            pendingCompletion = nil
            prior(nil)
        }
        pendingCompletion = handler

        previewTask = Task { [weak self] in
            do {
                let html = try await Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    let markdownText = try String(contentsOf: url, encoding: .utf8)
                    try Task.checkCancellation()
                    let htmlBody = MarkdownRenderer.renderHTML(markdownText)
                    return Self.previewHTML(for: htmlBody)
                }.value
                try Task.checkCancellation()

                await MainActor.run {
                    guard let self else { return }
                    self.previewTask = nil
                    self.webView.loadHTMLString(html, baseURL: MermaidSupport.resourceBaseURL)
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard let self else { return }
                    self.previewTask = nil
                    // Cancellation here means a newer preparePreview call came
                    // in; the new handler owns completion now.
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.previewTask = nil
                    if let handler = self.pendingCompletion {
                        self.pendingCompletion = nil
                        handler(error)
                    }
                }
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let handler = pendingCompletion else { return }
        pendingCompletion = nil
        handler(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard let handler = pendingCompletion else { return }
        pendingCompletion = nil
        handler(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard let handler = pendingCompletion else { return }
        pendingCompletion = nil
        handler(error)
    }

    private static func previewHTML(for htmlBody: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(PreviewCSS.css())</style>
        <style>
        @media (max-width: 400px) {
            body { font-size: 14px; padding: 10px 20px 20px; }
        }
        </style>
        </head>
        <body>\(htmlBody)</body>
        \(MathSupport.scriptHTML(for: htmlBody))
        \(TableSupport.scriptHTML(for: htmlBody))
        \(MermaidSupport.scriptHTML)
        \(SyntaxHighlightSupport.scriptHTML(for: htmlBody))
        </html>
        """
    }

}
