import Cocoa
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
            <style>\(PreviewCSS.css())</style>
            </head>
            <body>\(htmlBody)</body>
            \(MermaidSupport.scriptHTML)
            </html>
            """

            webView.loadHTMLString(html, baseURL: MermaidSupport.resourceBaseURL)
            handler(nil)
        } catch {
            handler(error)
        }
    }
}
