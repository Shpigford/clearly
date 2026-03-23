import AppKit
import WebKit

final class PDFExporter: NSObject, WKNavigationDelegate {
    private static var current: PDFExporter?
    private static let pageSize = NSSize(width: 612, height: 792)
    private static let margin: CGFloat = 54 // 0.75 inch
    private static let contentWidth = pageSize.width - (margin * 2)

    private var webView: WKWebView?
    private var hiddenWindow: NSWindow?
    private var exportURL: URL?
    private var documentURL: URL?
    private var isPrint = false

    func exportPDF(markdown: String, fontSize: CGFloat, fileURL: URL? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "Untitled.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        PDFExporter.current = self
        exportURL = url
        documentURL = fileURL
        isPrint = false
        loadHTML(markdown: markdown, fontSize: fontSize)
    }

    func printHTML(markdown: String, fontSize: CGFloat, fileURL: URL? = nil) {
        PDFExporter.current = self
        exportURL = nil
        documentURL = fileURL
        isPrint = true
        loadHTML(markdown: markdown, fontSize: fontSize)
    }

    private func loadHTML(markdown: String, fontSize: CGFloat) {
        let renderWidth = isPrint ? Self.pageSize.width : Self.contentWidth
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
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>\(PreviewCSS.css(fontSize: fontSize, forExport: !isPrint))</style>
        </head>
        <body>\(htmlBody)</body>
        \(MathSupport.scriptHTML(for: htmlBody))
        </html>
        """
        wv.loadHTMLString(html, baseURL: MermaidSupport.resourceBaseURL)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            do {
                try await waitForImages(in: webView)
            } catch {
                // If image waiting JS fails, continue with export/print instead of blocking.
            }

            if isPrint {
                let printInfo = makePrintInfo()
                let op = webView.printOperation(with: printInfo)
                op.showsPrintPanel = true
                op.showsProgressPanel = true
                if let window = NSApp.mainWindow {
                    op.runModal(for: window, delegate: self, didRun: #selector(operationDidRun(_:success:contextInfo:)), contextInfo: nil)
                } else {
                    _ = op.run()
                    cleanup()
                }
            } else {
                do {
                    guard let exportURL else {
                        cleanup()
                        return
                    }
                    let scrollHeight = try await documentHeight(in: webView)
                    let breakPoints = try await pageBreakPositions(in: webView)
                    let data = try await tallPDFData(in: webView, height: scrollHeight)
                    try writePaginatedPDF(sourceData: data, breakPoints: breakPoints, to: exportURL)
                } catch {
                    showExportError(error)
                }
                cleanup()
            }
        }
    }

    @objc private func operationDidRun(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        cleanup()
    }

    private func cleanup() {
        hiddenWindow?.orderOut(nil)
        webView = nil
        hiddenWindow = nil
        exportURL = nil
        documentURL = nil
        PDFExporter.current = nil
    }

    // MARK: - Print

    private func makePrintInfo() -> NSPrintInfo {
        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
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

    // MARK: - Export helpers

    private func documentHeight(in webView: WKWebView) async throws -> CGFloat {
        let value = try await webView.evaluateJavaScript("document.documentElement.scrollHeight")
        guard let number = value as? NSNumber else {
            throw ExportError.invalidDocumentHeight
        }
        return CGFloat(number.doubleValue)
    }

    private func pageBreakPositions(in webView: WKWebView) async throws -> [CGFloat] {
        let js = """
        Array.from(document.querySelectorAll('.page-break, [style*=\"page-break\"]')).map(
            el => el.getBoundingClientRect().top + window.scrollY
        )
        """
        let value = try await webView.evaluateJavaScript(js)
        guard let positions = value as? [NSNumber] else { return [] }
        return positions.map { CGFloat($0.doubleValue) }
    }

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

    private func tallPDFData(in webView: WKWebView, height: CGFloat) async throws -> Data {
        let config = WKPDFConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: Self.contentWidth, height: height)
        return try await webView.pdf(configuration: config)
    }

    private func writePaginatedPDF(sourceData: Data, breakPoints: [CGFloat], to url: URL) throws {
        guard let provider = CGDataProvider(data: sourceData as CFData),
              let source = CGPDFDocument(provider),
              let sourcePage = source.page(at: 1) else {
            throw ExportError.invalidSourcePDF
        }

        let sourceBox = sourcePage.getBoxRect(.mediaBox)
        let sourceHeight = sourceBox.height
        let contentHeight = Self.pageSize.height - (Self.margin * 2)
        let sortedBreaks = breakPoints.sorted()

        // Build slice boundaries (Y offsets from top of source)
        var sliceStarts: [CGFloat] = [0]
        var y: CGFloat = 0
        while y < sourceHeight {
            var nextY = y + contentHeight

            // Honor forced page breaks within this slice
            for bp in sortedBreaks {
                if bp > y && bp < nextY {
                    nextY = bp
                    break
                }
            }

            nextY = min(nextY, sourceHeight)
            if nextY <= y { break }
            if nextY < sourceHeight {
                sliceStarts.append(nextY)
            }
            y = nextY
        }

        // Create output PDF
        var mediaBox = CGRect(origin: .zero, size: Self.pageSize)
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw ExportError.cannotCreateOutput
        }

        for (i, sliceY) in sliceStarts.enumerated() {
            let nextSliceY = (i + 1 < sliceStarts.count) ? sliceStarts[i + 1] : sourceHeight

            ctx.beginPage(mediaBox: &mediaBox)
            ctx.saveGState()

            // Clip to the content area (inside margins)
            ctx.clip(to: CGRect(x: Self.margin, y: Self.margin, width: Self.contentWidth, height: contentHeight))

            // Translate so this slice's top aligns with the top of the content area.
            // In PDF coords (origin bottom-left): source top = sourceHeight.
            // We want source Y = (sourceHeight - sliceY) to land at output Y = (margin + contentHeight).
            let translateY = Self.margin + contentHeight - sourceHeight + sliceY
            ctx.translateBy(x: Self.margin, y: translateY)
            ctx.drawPDFPage(sourcePage)

            ctx.restoreGState()
            ctx.endPage()
        }

        ctx.closePDF()
    }

    private func showExportError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

private enum ExportError: LocalizedError {
    case invalidDocumentHeight
    case invalidSourcePDF
    case cannotCreateOutput

    var errorDescription: String? {
        switch self {
        case .invalidDocumentHeight:
            return "Could not measure the document for PDF export."
        case .invalidSourcePDF:
            return "Could not generate the intermediate PDF for export."
        case .cannotCreateOutput:
            return "Could not create the exported PDF file."
        }
    }
}
