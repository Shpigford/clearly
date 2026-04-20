import Cocoa
import ClearlyCore
import QuickLookUI
import WebKit

class PreviewViewController: NSViewController, QLPreviewingController {
    private var webView: WKWebView!

    override func loadView() {
        webView = WKWebView()
        self.view = webView
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let markdownText = try String(contentsOf: url, encoding: .utf8)
            let htmlBody = MarkdownRenderer.renderHTML(markdownText)

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

            webView.loadHTMLString(html, baseURL: MermaidSupport.resourceBaseURL)
            handler(nil)
        } catch {
            handler(error)
        }
    }
}
