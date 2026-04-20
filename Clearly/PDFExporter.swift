import AppKit
import ClearlyCore
import WebKit

final class PDFExporter: NSObject, WKNavigationDelegate {
    private static var current: PDFExporter?
    private static let pageSize = NSSize(width: 612, height: 792)
    private static let margin: CGFloat = 54 // 0.75 inch

    private var webView: WKWebView?
    private var hiddenWindow: NSWindow?
    private var exportURL: URL?
    private var documentURL: URL?
    private var isPrint = false

    func exportPDF(markdown: String, fontSize: CGFloat, fontFamily: String = "sanFrancisco", fileURL: URL? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Untitled.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        PDFExporter.current = self
        exportURL = url
        documentURL = fileURL
        isPrint = false
        loadHTML(markdown: markdown, fontSize: fontSize, fontFamily: fontFamily)
    }

    func printHTML(markdown: String, fontSize: CGFloat, fontFamily: String = "sanFrancisco", fileURL: URL? = nil) {
        PDFExporter.current = self
        exportURL = nil
        documentURL = fileURL
        isPrint = true
        loadHTML(markdown: markdown, fontSize: fontSize, fontFamily: fontFamily)
    }

    private func loadHTML(markdown: String, fontSize: CGFloat, fontFamily: String = "sanFrancisco") {
        // Both print and export use full page width — NSPrintOperation handles margins
        let renderWidth = Self.pageSize.width
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalImageSchemeHandler(), forURLScheme: LocalImageSupport.scheme)
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: renderWidth, height: Self.pageSize.height), configuration: config)
        wv.navigationDelegate = self
        self.webView = wv

        // WKWebView must be in a window for printOperation to work
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: renderWidth, height: Self.pageSize.height),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = wv
        window.orderBack(nil)
        self.hiddenWindow = window

        let rawBody = MarkdownRenderer.renderHTML(markdown)
        let htmlBody = LocalImageSupport.resolveImageSources(in: rawBody, relativeTo: documentURL)
        // Both paths use forExport: false so @media print rules (including page-break) apply
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>\(PreviewCSS.css(fontSize: fontSize, fontFamily: fontFamily, forExport: false))</style>
        </head>
        <body>\(htmlBody)</body>
        \(MathSupport.scriptHTML(for: htmlBody))
        \(TableSupport.scriptHTML(for: htmlBody))
        \(SyntaxHighlightSupport.scriptHTML(for: htmlBody))
        </html>
        """
        wv.loadHTMLString(html, baseURL: documentURL?.deletingLastPathComponent() ?? MermaidSupport.resourceBaseURL)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Detach delegate immediately to prevent re-entrancy from print operations
        webView.navigationDelegate = nil

        Task { @MainActor in
            do {
                try await waitForImages(in: webView)
            } catch {
                // If image waiting JS fails, continue instead of blocking.
            }

            let isExport = !isPrint
            let printInfo = makePrintInfo(forExport: isExport)

            guard let window = NSApp.mainWindow ?? self.hiddenWindow else {
                cleanup()
                return
            }

            if isPrint {
                let op = webView.printOperation(with: printInfo)
                op.showsPrintPanel = true
                op.showsProgressPanel = true
                op.runModal(for: window, delegate: self, didRun: #selector(operationDidRun(_:success:contextInfo:)), contextInfo: nil)
            } else {
                guard let exportURL else {
                    cleanup()
                    return
                }
                // Use WebKit's native print pagination engine via NSPrintOperation.
                // This is the only way to get proper page breaks that never cut through
                // text lines. CSS @media print rules (page-break-inside: avoid) are
                // respected by this codepath.
                printInfo.jobDisposition = .save
                printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = exportURL

                let op = webView.printOperation(with: printInfo)
                op.showsPrintPanel = false
                op.showsProgressPanel = false
                op.runModal(for: window, delegate: self, didRun: #selector(operationDidRun(_:success:contextInfo:)), contextInfo: nil)
            }
        }
    }

    @objc private func operationDidRun(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !success && !self.isPrint {
                self.showExportError(ExportError.exportFailed)
            }
            self.cleanup()
        }
    }

    private func cleanup() {
        hiddenWindow?.orderOut(nil)
        webView?.navigationDelegate = nil
        webView = nil
        hiddenWindow = nil
        exportURL = nil
        documentURL = nil
        PDFExporter.current = nil
    }

    // MARK: - Print

    private func makePrintInfo(forExport: Bool) -> NSPrintInfo {
        let printInfo: NSPrintInfo
        if forExport {
            printInfo = NSPrintInfo(dictionary: [:])
            printInfo.scalingFactor = 1.0
            printInfo.orientation = .portrait
            printInfo.isSelectionOnly = false
        } else {
            printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        }

        printInfo.paperSize = Self.pageSize
        printInfo.topMargin = Self.margin
        printInfo.bottomMargin = Self.margin
        printInfo.leftMargin = Self.margin
        printInfo.rightMargin = Self.margin
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        return printInfo
    }

    // MARK: - Helpers

    private func waitForImages(in webView: WKWebView) async throws {
        _ = try await webView.callAsyncJavaScript(
            """
            const pendingImages = Array.from(document.images).filter(img => !img.complete);
            if (pendingImages.length) {
                await Promise.all(
                    pendingImages.map(img => new Promise(resolve => {
                        let settled = false;
                        const finish = () => {
                            if (settled) return;
                            settled = true;
                            clearTimeout(timeout);
                            resolve(null);
                        };
                        const timeout = setTimeout(finish, 1000);
                        img.addEventListener('load', finish, { once: true });
                        img.addEventListener('error', finish, { once: true });
                    }))
                );
            }
            await new Promise(resolve => setTimeout(resolve, 50));
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
    }

    private func showExportError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

private enum ExportError: LocalizedError {
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .exportFailed:
            return "Could not export the PDF file."
        }
    }
}
