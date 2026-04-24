import AppKit
import ClearlyCore

enum TextCheckingPreferences {
    private static let continuousSpellCheckingKey = "continuousSpellCheckingEnabled"
    private static let grammarCheckingKey = "grammarCheckingEnabled"
    private static let automaticSpellingCorrectionKey = "automaticSpellingCorrectionEnabled"

    static func apply(to textView: NSTextView) {
        textView.isContinuousSpellCheckingEnabled = UserDefaults.standard.object(forKey: continuousSpellCheckingKey) as? Bool ?? true
        textView.isGrammarCheckingEnabled = UserDefaults.standard.object(forKey: grammarCheckingKey) as? Bool ?? true
        textView.isAutomaticSpellingCorrectionEnabled = UserDefaults.standard.object(forKey: automaticSpellingCorrectionKey) as? Bool ?? false
    }

    static func persist(from textView: NSTextView) {
        UserDefaults.standard.set(textView.isContinuousSpellCheckingEnabled, forKey: continuousSpellCheckingKey)
        UserDefaults.standard.set(textView.isGrammarCheckingEnabled, forKey: grammarCheckingKey)
        UserDefaults.standard.set(textView.isAutomaticSpellingCorrectionEnabled, forKey: automaticSpellingCorrectionKey)
    }
}

class PersistentTextCheckingTextView: NSTextView {
    @objc override func toggleContinuousSpellChecking(_ sender: Any?) {
        super.toggleContinuousSpellChecking(sender)
        TextCheckingPreferences.persist(from: self)
    }

    @objc override func toggleGrammarChecking(_ sender: Any?) {
        super.toggleGrammarChecking(sender)
        TextCheckingPreferences.persist(from: self)
    }

    @objc override func toggleAutomaticSpellingCorrection(_ sender: Any?) {
        super.toggleAutomaticSpellingCorrection(sender)
        TextCheckingPreferences.persist(from: self)
    }
}

final class ClearlyTextView: PersistentTextCheckingTextView {
    var documentURL: URL?
    var onShowFind: (() -> Void)?
    var onWikiLinkClicked: ((String, String?) -> Void)?

    /// Invoked when the user pastes/drops an image into an unsaved document.
    /// Implementer shows the NSSavePanel, returning the saved URL on success
    /// or `nil` on cancel. Called synchronously from `paste(_:)` /
    /// `performDragOperation(_:)`, so the panel's modal run is fine.
    var onPasteRequiresSave: (() -> URL?)?

    // MARK: - Wiki-Link Cmd+Click

    private static let wikiLinkRegex = try! NSRegularExpression(
        pattern: #"\[\[([^\]\|#\^]+?)(?:#([^\]\|]+?))?(?:\|[^\]]+?)?\]\]"#
    )

    override func mouseDown(with event: NSEvent) {
        if WikiLinkCompletionManager.shared.isVisible {
            WikiLinkCompletionManager.shared.dismiss()
        }
        if event.modifierFlags.contains(.command),
           let lm = layoutManager, let tc = textContainer {
            let viewPoint = convert(event.locationInWindow, from: nil)
            let containerPoint = NSPoint(
                x: viewPoint.x - textContainerInset.width,
                y: viewPoint.y - textContainerInset.height
            )
            var fraction: CGFloat = 0
            let charIndex = lm.characterIndex(
                for: containerPoint, in: tc,
                fractionOfDistanceBetweenInsertionPoints: &fraction
            )
            if charIndex < (string as NSString).length,
               let (target, heading) = wikiLinkAt(charIndex: charIndex) {
                onWikiLinkClicked?(target, heading)
                return
            }
        }
        super.mouseDown(with: event)
    }

    private func wikiLinkAt(charIndex: Int) -> (target: String, heading: String?)? {
        let text = string as NSString
        let searchStart = max(0, charIndex - 200)
        let searchEnd = min(text.length, charIndex + 200)
        let searchRange = NSRange(location: searchStart, length: searchEnd - searchStart)

        for match in Self.wikiLinkRegex.matches(in: string, range: searchRange) {
            guard NSLocationInRange(charIndex, match.range) else { continue }
            let target = text.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespaces)
            var heading: String? = nil
            if match.range(at: 2).location != NSNotFound {
                heading = text.substring(with: match.range(at: 2))
                    .trimmingCharacters(in: .whitespaces)
            }
            return (target, heading)
        }
        return nil
    }

    // MARK: - Cursor

    // Hide the macOS 14+ system insertion indicator so our custom drawInsertionPoint is visible
    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if let indicator = subview as? NSTextInsertionIndicator {
            indicator.displayMode = .hidden
        }
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var adjusted = rect
        adjusted.size.width = 2
        super.drawInsertionPoint(in: adjusted, color: color, turnedOn: flag)
    }

    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        var rect = rect
        rect.size.width += 2
        super.setNeedsDisplay(rect, avoidAdditionalLayout: flag)
    }

    // MARK: - Print

    override func printView(_ sender: Any?) {
        let fontSize = UserDefaults.standard.double(forKey: "editorFontSize")
        let fontFamily = UserDefaults.standard.string(forKey: "previewFontFamily") ?? "sanFrancisco"
        PDFExporter().printHTML(
            markdown: string,
            fontSize: CGFloat(fontSize > 0 ? fontSize : Theme.editorFontSize),
            fontFamily: fontFamily,
            fileURL: documentURL
        )
    }

    // MARK: - Paste

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        if handleIncomingPasteboard(pasteboard) { return }

        if let plainText = pasteboard.string(forType: .string) {
            insertText(plainText, replacementRange: selectedRange())
        } else {
            super.paste(sender)
        }
    }

    @discardableResult
    private func handleIncomingPasteboard(
        _ pasteboard: NSPasteboard
    ) -> Bool {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            let urlNames = urls.map(\.lastPathComponent).joined(separator: ",")
            DiagnosticLog.log("handleIncomingPasteboard file URLs: \(urlNames)")
            let imageURLs = urls.filter {
                ImagePasteService.imageFileExtensions.contains($0.pathExtension.lowercased())
            }
            if !imageURLs.isEmpty {
                return handleImageFileURLs(imageURLs)
            }
        }

        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil),
           let image = NSImage(pasteboard: pasteboard),
           let png = Self.pngData(from: image) {
            return insertPastedPNG(png)
        }

        if let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.contains("\n"), !text.contains(" "),
           let url = URL(string: text), ImagePasteService.isLikelyImageURL(url) {
            return beginImageDownload(from: url)
        }

        return false
    }

    // MARK: - Image-paste helpers

    @discardableResult
    private func handleImageFileURLs(_ urls: [URL]) -> Bool {
        guard let docURL = resolveDocumentURLForPaste() else {
            DiagnosticLog.log("handleImageFileURLs: no document URL, aborting")
            return false
        }
        var tokens: [String] = []
        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                let ext = url.pathExtension.lowercased()
                let result = try ImagePasteService.writeImageData(
                    data,
                    ext: ext,
                    besidesDocumentAt: docURL,
                    presenter: nil
                )
                tokens.append(result.markdown)
            } catch {
                DiagnosticLog.log("handleImageFileURLs: \(url.lastPathComponent) error: \(error.localizedDescription)")
            }
        }
        guard !tokens.isEmpty else { return false }
        insertText(tokens.joined(separator: "\n"), replacementRange: selectedRange())
        return true
    }

    @discardableResult
    private func insertPastedPNG(_ png: Data) -> Bool {
        guard let docURL = resolveDocumentURLForPaste() else { return false }
        do {
            let result = try ImagePasteService.writePNG(png, besidesDocumentAt: docURL, presenter: nil)
            insertText(result.markdown, replacementRange: selectedRange())
            return true
        } catch {
            DiagnosticLog.log("Paste: failed to write sibling PNG: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    private func beginImageDownload(from url: URL) -> Bool {
        guard let docURL = resolveDocumentURLForPaste() else { return false }
        let token = UUID().uuidString
        let placeholder = "![](downloading…)<!--clearly-paste:\(token)-->"
        insertText(placeholder, replacementRange: selectedRange())
        Task { @MainActor [weak self] in
            do {
                let png = try await ImageDownloader.fetchImagePNG(from: url)
                guard let self else { return }
                let result = try ImagePasteService.writePNG(png, besidesDocumentAt: docURL, presenter: nil)
                self.replacePlaceholder(placeholder, with: result.markdown)
            } catch {
                DiagnosticLog.log("Paste: image download failed for \(url): \(error.localizedDescription)")
                self?.replacePlaceholder(placeholder, with: "![](failed-download)")
            }
        }
        return true
    }

    private func replacePlaceholder(_ placeholder: String, with replacement: String) {
        let ns = string as NSString
        let range = ns.range(of: placeholder)
        guard range.location != NSNotFound else { return }
        insertText(replacement, replacementRange: range)
    }

    private func resolveDocumentURLForPaste() -> URL? {
        if let documentURL { return documentURL }
        if let saved = onPasteRequiresSave?() {
            documentURL = saved
            return saved
        }
        NSSound.beep()
        return nil
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func pngData(from data: Data) -> Data? {
        // Route through NSImage so ImageIO handles HEIC, WebP, GIF, etc. —
        // NSBitmapImageRep's direct decode has narrower format support.
        guard let image = NSImage(data: data) else { return nil }
        return pngData(from: image)
    }

    // MARK: - Find

    @objc func showFindPanel(_ sender: Any?) {
        onShowFind?()
    }

    // MARK: - Wiki-Link Completion Keyboard

    override func keyDown(with event: NSEvent) {
        let completion = WikiLinkCompletionManager.shared
        guard completion.isVisible else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 125: completion.moveSelectionDown()          // Down arrow
        case 126: completion.moveSelectionUp()            // Up arrow
        case 36, 48:                                      // Return, Tab
            if completion.hasSelection {
                completion.insertSelectedCompletion()
            } else {
                completion.dismiss()
                super.keyDown(with: event)                // Pass through so Enter inserts newline
            }
        case 53: completion.dismiss()                     // Escape
        case 123, 124:                                    // Left, Right arrow
            completion.dismiss()
            super.keyDown(with: event)
        default: super.keyDown(with: event)               // Pass through
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        if event.charactersIgnoringModifiers == "f" {
            onShowFind?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Markdown Formatting

    @objc func toggleBold(_ sender: Any?) {
        wrapSelection(prefix: "**", suffix: "**", placeholder: "bold text")
    }

    @objc func toggleItalic(_ sender: Any?) {
        wrapSelection(prefix: "*", suffix: "*", placeholder: "italic text")
    }

    @objc func insertLink(_ sender: Any?) {
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range)
        if selected.isEmpty {
            insertText("[link text](url)", replacementRange: range)
            let urlStart = range.location + "[link text](".utf16.count
            setSelectedRange(NSRange(location: urlStart, length: "url".utf16.count))
        } else {
            insertText("[\(selected)](url)", replacementRange: range)
            let urlStart = range.location + "[\(selected)](".utf16.count
            setSelectedRange(NSRange(location: urlStart, length: "url".utf16.count))
        }
    }

    @objc func insertHeading(_ sender: Any?) {
        let range = selectedRange()
        let lineRange = (string as NSString).lineRange(for: range)
        let line = (string as NSString).substring(with: lineRange)

        // Cycle: no heading -> # -> ## -> ### -> remove
        let trimmed = line.drop(while: { $0 == "#" || $0 == " " })
        let hashes = line.prefix(while: { $0 == "#" })

        let newLine: String
        switch hashes.count {
        case 0: newLine = "# \(trimmed)"
        case 1: newLine = "## \(trimmed)"
        case 2: newLine = "### \(trimmed)"
        default: newLine = String(trimmed)
        }

        insertText(newLine, replacementRange: lineRange)
    }

    @objc func toggleStrikethrough(_ sender: Any?) {
        wrapSelection(prefix: "~~", suffix: "~~", placeholder: "strikethrough text")
    }

    @objc func insertImage(_ sender: Any?) {
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range)
        if selected.isEmpty {
            insertText("![alt text](url)", replacementRange: range)
            let urlStart = range.location + "![alt text](".utf16.count
            setSelectedRange(NSRange(location: urlStart, length: "url".utf16.count))
        } else {
            insertText("![\(selected)](url)", replacementRange: range)
            let urlStart = range.location + "![\(selected)](".utf16.count
            setSelectedRange(NSRange(location: urlStart, length: "url".utf16.count))
        }
    }

    @objc func toggleBulletList(_ sender: Any?) {
        toggleLinePrefix(prefix: "- ", placeholder: "list item")
    }

    @objc func toggleNumberedList(_ sender: Any?) {
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range)
        if selected.isEmpty {
            insertText("1. list item", replacementRange: range)
            let start = range.location + "1. ".utf16.count
            setSelectedRange(NSRange(location: start, length: "list item".utf16.count))
            return
        }
        let lineRange = (string as NSString).lineRange(for: range)
        let block = (string as NSString).substring(with: lineRange)
        let lines = block.components(separatedBy: "\n")
        var result: [String] = []
        var num = 1
        for line in lines {
            if line.isEmpty {
                result.append(line)
            } else {
                result.append("\(num). \(line)")
                num += 1
            }
        }
        insertText(result.joined(separator: "\n"), replacementRange: lineRange)
    }

    @objc func toggleTodoList(_ sender: Any?) {
        toggleLinePrefix(prefix: "- [ ] ", placeholder: "task")
    }

    @objc func toggleBlockquote(_ sender: Any?) {
        toggleLinePrefix(prefix: "> ", placeholder: "quote")
    }

    @objc func insertHorizontalRule(_ sender: Any?) {
        let range = selectedRange()
        insertText("\n\n---\n\n", replacementRange: range)
    }

    @objc func insertMarkdownTable(_ sender: Any?) {
        let range = selectedRange()
        let table = "| Column 1 | Column 2 | Column 3 |\n| --- | --- | --- |\n| Cell | Cell | Cell |"
        insertText(table, replacementRange: range)
    }

    @objc func toggleInlineCode(_ sender: Any?) {
        wrapSelection(prefix: "`", suffix: "`", placeholder: "code")
    }

    @objc func insertCodeBlock(_ sender: Any?) {
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range)
        if selected.isEmpty {
            let snippet = "```\ncode\n```"
            insertText(snippet, replacementRange: range)
            let start = range.location + "```\n".utf16.count
            setSelectedRange(NSRange(location: start, length: "code".utf16.count))
        } else {
            insertText("```\n\(selected)\n```", replacementRange: range)
        }
    }

    @objc func toggleInlineMath(_ sender: Any?) {
        wrapSelection(prefix: "$", suffix: "$", placeholder: "math")
    }

    @objc func insertMathBlock(_ sender: Any?) {
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range)
        if selected.isEmpty {
            let snippet = "$$\nmath\n$$"
            insertText(snippet, replacementRange: range)
            let start = range.location + "$$\n".utf16.count
            setSelectedRange(NSRange(location: start, length: "math".utf16.count))
        } else {
            insertText("$$\n\(selected)\n$$", replacementRange: range)
        }
    }

    @objc func insertPageBreak(_ sender: Any?) {
        let range = selectedRange()
        let snippet = "\n\n<div class=\"page-break\"></div>\n\n"
        insertText(snippet, replacementRange: range)
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()

        let formatMenu = NSMenu(title: "Text Format")

        formatMenu.addItem(withTitle: "Headers", action: #selector(insertHeading(_:)), keyEquivalent: "")
        formatMenu.addItem(.separator())

        let boldItem = formatMenu.addItem(withTitle: "Bold", action: #selector(toggleBold(_:)), keyEquivalent: "b")
        boldItem.keyEquivalentModifierMask = .command
        let italicItem = formatMenu.addItem(withTitle: "Italic", action: #selector(toggleItalic(_:)), keyEquivalent: "i")
        italicItem.keyEquivalentModifierMask = .command
        let strikeItem = formatMenu.addItem(withTitle: "Strikethrough", action: #selector(toggleStrikethrough(_:)), keyEquivalent: "x")
        strikeItem.keyEquivalentModifierMask = [.command, .shift]
        formatMenu.addItem(.separator())

        formatMenu.addItem(withTitle: "Insert Link", action: #selector(insertLink(_:)), keyEquivalent: "")
        formatMenu.addItem(withTitle: "Insert Image", action: #selector(insertImage(_:)), keyEquivalent: "")
        formatMenu.addItem(.separator())

        formatMenu.addItem(withTitle: "List", action: #selector(toggleBulletList(_:)), keyEquivalent: "")
        formatMenu.addItem(withTitle: "Ordered List", action: #selector(toggleNumberedList(_:)), keyEquivalent: "")
        formatMenu.addItem(withTitle: "Todo", action: #selector(toggleTodoList(_:)), keyEquivalent: "")
        formatMenu.addItem(.separator())

        formatMenu.addItem(withTitle: "Quote", action: #selector(toggleBlockquote(_:)), keyEquivalent: "")
        formatMenu.addItem(withTitle: "Horizontal Rule", action: #selector(insertHorizontalRule(_:)), keyEquivalent: "")
        formatMenu.addItem(withTitle: "Table", action: #selector(insertMarkdownTable(_:)), keyEquivalent: "")
        formatMenu.addItem(.separator())

        formatMenu.addItem(withTitle: "Code", action: #selector(toggleInlineCode(_:)), keyEquivalent: "")
        formatMenu.addItem(withTitle: "Code Block", action: #selector(insertCodeBlock(_:)), keyEquivalent: "")
        formatMenu.addItem(.separator())

        formatMenu.addItem(withTitle: "Math", action: #selector(toggleInlineMath(_:)), keyEquivalent: "")
        formatMenu.addItem(withTitle: "Math Block", action: #selector(insertMathBlock(_:)), keyEquivalent: "")

        let formatItem = NSMenuItem(title: "Text Format", action: nil, keyEquivalent: "")
        formatItem.submenu = formatMenu

        menu.insertItem(.separator(), at: 0)
        menu.insertItem(formatItem, at: 0)

        return menu
    }

    // MARK: - Helpers

    private func toggleLinePrefix(prefix: String, placeholder: String) {
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range)
        if selected.isEmpty {
            let text = "\(prefix)\(placeholder)"
            insertText(text, replacementRange: range)
            let start = range.location + prefix.utf16.count
            setSelectedRange(NSRange(location: start, length: placeholder.utf16.count))
            return
        }
        let lineRange = (string as NSString).lineRange(for: range)
        let block = (string as NSString).substring(with: lineRange)
        let lines = block.components(separatedBy: "\n")
        let result = lines.map { $0.isEmpty ? $0 : "\(prefix)\($0)" }
        insertText(result.joined(separator: "\n"), replacementRange: lineRange)
    }

    private func wrapSelection(prefix: String, suffix: String, placeholder: String) {
        let range = selectedRange()
        let selected = (string as NSString).substring(with: range)
        if selected.isEmpty {
            let text = "\(prefix)\(placeholder)\(suffix)"
            insertText(text, replacementRange: range)
            let placeholderStart = range.location + prefix.utf16.count
            setSelectedRange(NSRange(location: placeholderStart, length: placeholder.utf16.count))
        } else {
            let text = "\(prefix)\(selected)\(suffix)"
            insertText(text, replacementRange: range)
        }
    }
}
