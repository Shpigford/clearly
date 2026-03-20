import AppKit

final class ClearlyTextView: NSTextView {

    // MARK: - Print

    override func printView(_ sender: Any?) {
        let fontSize = UserDefaults.standard.double(forKey: "editorFontSize")
        PDFExporter().printHTML(markdown: string, fontSize: CGFloat(fontSize > 0 ? fontSize : 16))
    }

    // MARK: - Find

    @objc func showFindPanel(_ sender: Any?) {
        let item = NSMenuItem()
        item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        performFindPanelAction(item)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        if event.charactersIgnoringModifiers == "f" {
            showFindPanel(nil)
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

    @objc func insertPageBreak(_ sender: Any?) {
        let range = selectedRange()
        let snippet = "\n\n<div class=\"page-break\"></div>\n\n"
        insertText(snippet, replacementRange: range)
    }

    // MARK: - Helpers

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
