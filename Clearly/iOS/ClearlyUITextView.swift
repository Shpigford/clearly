import UIKit
import ClearlyCore

/// UITextView configured for markdown editing: monospaced typing attributes, editor
/// background/tint, autocorrect/smart-quote disabled, vault-appropriate insets.
/// The highlighter is owned by `EditorView_iOS.Coordinator`, mirroring the Mac pattern
/// where highlighting is driven by the delegate rather than the view.
final class ClearlyUITextView: UITextView {

    /// Path of the open `.md` document. Set by `EditorView_iOS` each update
    /// pass so paste/drop handlers can compute sibling image URLs.
    var documentURL: URL?

    init() {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: .zero)
        container.widthTracksTextView = true
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)

        super.init(frame: .zero, textContainer: container)

        backgroundColor = Theme.backgroundColor
        textColor = Theme.textColor
        font = Theme.editorFont
        tintColor = Theme.accentColor
        isEditable = true
        isSelectable = true
        allowsEditingTextAttributes = false
        autocapitalizationType = .none
        autocorrectionType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        spellCheckingType = .no
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive

        textContainerInset = UIEdgeInsets(
            top: Theme.editorInsetTop,
            left: 16,
            bottom: Theme.editorInsetBottom,
            right: 16
        )

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Theme.editorLineHeight
        paragraph.maximumLineHeight = Theme.editorLineHeight
        typingAttributes = [
            .font: Theme.editorFont,
            .foregroundColor: Theme.textColor,
            .paragraphStyle: paragraph,
            .baselineOffset: Theme.editorBaselineOffset
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Paste

    override func paste(_ sender: Any?) {
        let pb = UIPasteboard.general

        // 1. Raw image on pasteboard — normalize HEIC/JPEG/etc. to PNG.
        if pb.hasImages, let image = pb.image, let png = image.pngData() {
            insertPastedPNG(png)
            return
        }

        // 2. URL object on pasteboard that looks like an image — download.
        if pb.hasURLs, let url = pb.urls?.first, ImagePasteService.isLikelyImageURL(url) {
            beginImageDownload(from: url)
            return
        }

        // 3. Plain string that parses into an http(s) image URL — download.
        if pb.hasStrings,
           let raw = pb.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.contains("\n"), !raw.contains(" "),
           let url = URL(string: raw), ImagePasteService.isLikelyImageURL(url) {
            beginImageDownload(from: url)
            return
        }

        super.paste(sender)
    }

    /// Public entry for the drop delegate in `EditorView_iOS` — inserts the
    /// image at the currently-selected range after writing a sibling PNG.
    func handleDroppedImageData(_ data: Data) {
        guard let image = UIImage(data: data), let png = image.pngData() else {
            DiagnosticLog.log("iOS drop: failed to decode image data")
            return
        }
        insertPastedPNG(png)
    }

    // MARK: - Image-paste helpers

    private func insertPastedPNG(_ png: Data) {
        guard let docURL = documentURL else {
            DiagnosticLog.log("iOS paste: documentURL not set, cannot write sibling PNG")
            return
        }
        do {
            let result = try ImagePasteService.writePNG(png, besidesDocumentAt: docURL, presenter: nil)
            insertMarkdown(result.markdown)
        } catch {
            DiagnosticLog.log("iOS paste: failed to write sibling PNG: \(error.localizedDescription)")
        }
    }

    private func beginImageDownload(from url: URL) {
        guard let docURL = documentURL else {
            DiagnosticLog.log("iOS paste: documentURL not set, cannot download")
            return
        }
        let token = UUID().uuidString
        let placeholder = "![](downloading…)<!--clearly-paste:\(token)-->"
        insertMarkdown(placeholder)
        Task { @MainActor [weak self] in
            do {
                let png = try await ImageDownloader.fetchImagePNG(from: url)
                guard let self else { return }
                let result = try ImagePasteService.writePNG(png, besidesDocumentAt: docURL, presenter: nil)
                self.replacePlaceholder(placeholder, with: result.markdown)
            } catch {
                DiagnosticLog.log("iOS paste: image download failed for \(url): \(error.localizedDescription)")
                self?.replacePlaceholder(placeholder, with: "![](failed-download)")
            }
        }
    }

    private func insertMarkdown(_ markdown: String) {
        let range = selectedRange
        let current = (text ?? "") as NSString
        let updated = current.replacingCharacters(in: range, with: markdown)
        text = updated
        let caret = range.location + (markdown as NSString).length
        selectedRange = NSRange(location: caret, length: 0)
        delegate?.textViewDidChange?(self)
    }

    private func replacePlaceholder(_ placeholder: String, with replacement: String) {
        let current = (text ?? "") as NSString
        let range = current.range(of: placeholder)
        guard range.location != NSNotFound else { return }
        let updated = current.replacingCharacters(in: range, with: replacement)
        text = updated
        delegate?.textViewDidChange?(self)
    }
}
