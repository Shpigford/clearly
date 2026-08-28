import AppKit
import ClearlyCore
import UniformTypeIdentifiers

@MainActor
enum DocumentExporter {
    static func exportRichText(markdown: String, sourceURL: URL?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.rtf]
        let baseName = sourceURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        panel.nameFieldStringValue = "\(baseName).rtf"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try richTextData(for: markdown).write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private static func richTextData(for markdown: String) throws -> Data {
        let html = """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"></head>
        <body>\(MarkdownRenderer.renderHTML(markdown))</body>
        </html>
        """

        guard let attributed = NSAttributedString(html: Data(html.utf8), documentAttributes: nil),
              let data = attributed.rtf(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [:]
              ) else {
            throw DocumentExportError.conversionFailed
        }
        return data
    }
}

private enum DocumentExportError: LocalizedError {
    case conversionFailed

    var errorDescription: String? {
        "Could not export this document as Rich Text."
    }
}
