import AppKit
import ClearlyCore

enum CopyActions {
    static func copyFilePath(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.path, forType: .string)
    }

    static func copyFileName(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.lastPathComponent, forType: .string)
    }

    static func copyRelativePath(_ url: URL, vaultRoot: URL) {
        let target = url.standardizedFileURL.path
        let root = vaultRoot.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        let relative: String
        if target == root {
            relative = ""
        } else if target.hasPrefix(prefix) {
            relative = String(target.dropFirst(prefix.count))
        } else {
            relative = url.lastPathComponent
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(relative, forType: .string)
    }

    static func copyWikiLink(_ target: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("[[\(target)]]", forType: .string)
    }

    static func copyMarkdown(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    static func copyHTML(_ text: String) {
        let html = MarkdownRenderer.renderHTML(text)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(html, forType: .html)
        pb.setString(html, forType: .string)
    }

    static func copyRichText(_ text: String) {
        let html = MarkdownRenderer.renderHTML(text)
        guard let data = html.data(using: .utf8),
              let attributed = NSAttributedString(html: data, documentAttributes: nil) else {
            // Fall back to plain HTML if conversion fails
            copyHTML(text)
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        if let rtfData = attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:]) {
            pb.setData(rtfData, forType: .rtf)
        }
        pb.setString(attributed.string, forType: .string)
    }

    static func copyPlainText(_ text: String) {
        let html = MarkdownRenderer.renderHTML(text)
        let plain: String
        if let data = html.data(using: .utf8),
           let attributed = NSAttributedString(html: data, documentAttributes: nil) {
            plain = attributed.string
        } else {
            // Fall back: strip HTML tags with regex
            plain = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(plain, forType: .string)
    }

    /// Reads markdown content from a file URL, using security-scoped access if needed.
    static func readMarkdown(from url: URL) -> String? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Builds an NSMenu with all copy items for a given file URL.
    static func copySubmenu(for url: URL, target: AnyObject) -> NSMenu {
        let sub = NSMenu(title: "Copy")

        let pathItem = NSMenuItem(title: "Copy File Path", action: #selector(CopyMenuActions.copyFilePathAction(_:)), keyEquivalent: "")
        pathItem.representedObject = url
        pathItem.target = target
        sub.addItem(pathItem)

        let nameItem = NSMenuItem(title: "Copy File Name", action: #selector(CopyMenuActions.copyFileNameAction(_:)), keyEquivalent: "")
        nameItem.representedObject = url
        nameItem.target = target
        sub.addItem(nameItem)

        sub.addItem(.separator())

        let mdItem = NSMenuItem(title: "Copy Markdown", action: #selector(CopyMenuActions.copyMarkdownAction(_:)), keyEquivalent: "")
        mdItem.representedObject = url
        mdItem.target = target
        sub.addItem(mdItem)

        let htmlItem = NSMenuItem(title: "Copy HTML", action: #selector(CopyMenuActions.copyHTMLAction(_:)), keyEquivalent: "")
        htmlItem.representedObject = url
        htmlItem.target = target
        sub.addItem(htmlItem)

        let richItem = NSMenuItem(title: "Copy Rich Text", action: #selector(CopyMenuActions.copyRichTextAction(_:)), keyEquivalent: "")
        richItem.representedObject = url
        richItem.target = target
        sub.addItem(richItem)

        let plainItem = NSMenuItem(title: "Copy Plain Text", action: #selector(CopyMenuActions.copyPlainTextAction(_:)), keyEquivalent: "")
        plainItem.representedObject = url
        plainItem.target = target
        sub.addItem(plainItem)

        return sub
    }
}

/// Objective-C selectors for NSMenu actions.
@objc protocol CopyMenuActions {
    func copyFilePathAction(_ sender: NSMenuItem)
    func copyFileNameAction(_ sender: NSMenuItem)
    func copyMarkdownAction(_ sender: NSMenuItem)
    func copyHTMLAction(_ sender: NSMenuItem)
    func copyRichTextAction(_ sender: NSMenuItem)
    func copyPlainTextAction(_ sender: NSMenuItem)
}
