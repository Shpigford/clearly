import UIKit
import ClearlyCore
import QuickLook
import WebKit

final class PreviewViewController: UIViewController, QLPreviewingController {
    private var webView: WKWebView!

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalImageSchemeHandler(), forURLScheme: LocalImageSupport.scheme)
        webView = WKWebView(frame: .zero, configuration: config)
        view = webView
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let markdownText = try String(contentsOf: url, encoding: .utf8)
            let rawBody = MarkdownRenderer.renderHTML(markdownText)
            let htmlBody = LocalImageSupport.resolveImageSources(in: rawBody, relativeTo: url)

            let html = """
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

            webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
            handler(nil)
        } catch {
            handler(error)
        }
    }
}
