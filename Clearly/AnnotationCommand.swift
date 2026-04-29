import AppKit
import ClearlyCore
import Foundation
import WebKit

extension Notification.Name {
    static let previewAnnotationCommand = Notification.Name("ClearlyPreviewAnnotationCommand")
}

enum AnnotationAuthor {
    static var current: String {
        NSUserName()
    }
}

enum AnnotationPrompt {
    static func requestComment(anchorScreenRect: NSRect? = nil) -> String? {
        AnnotationCommentPanel(anchorScreenRect: anchorScreenRect).run()
    }

    static func present(error: Error) {
        NSAlert(error: error).runModal()
    }
}

final class WebAnnotationContextMenuInstaller {
    private weak var webView: WKWebView?
    private let action: () -> Void

    init(webView: WKWebView, action: @escaping () -> Void) {
        self.webView = webView
        self.action = action
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuWillOpen(_:)),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func menuWillOpen(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu,
              let webView,
              shouldAugmentMenu(for: webView),
              !menu.items.contains(where: { $0.action == #selector(addAnnotation(_:)) }) else { return }

        menu.insertItem(.separator(), at: 0)
        let item = NSMenuItem(
            title: "Add Annotation...",
            action: #selector(addAnnotation(_:)),
            keyEquivalent: ""
        )
        item.target = self
        menu.insertItem(item, at: 0)
    }

    @objc private func addAnnotation(_ sender: Any?) {
        action()
    }

    private func shouldAugmentMenu(for webView: WKWebView) -> Bool {
        guard let window = webView.window, window.isKeyWindow else { return false }
        let mouse = window.mouseLocationOutsideOfEventStream
        let local = webView.convert(mouse, from: nil)
        return webView.bounds.contains(local)
    }
}

private final class AnnotationCommentPanel: NSObject {
    private let panel: NSPanel
    private let textView: NSTextView
    private let errorLabel: NSTextField
    private var result: String?

    init(anchorScreenRect: NSRect?) {
        let panelSize = NSSize(width: 380, height: 248)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Add Annotation"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .windowBackgroundColor

        let contentView = NSView(frame: NSRect(origin: .zero, size: panelSize))
        contentView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = contentView

        let titleLabel = NSTextField(labelWithString: "Add Annotation")
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)

        let subtitleLabel = NSTextField(labelWithString: "Comment on the selected text.")
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true

        textView = NSTextView()
        textView.minSize = NSSize(width: 0, height: 96)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 340, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        TextCheckingPreferences.apply(to: textView)
        scrollView.documentView = textView

        errorLabel = NSTextField(labelWithString: "Enter a comment before adding.")
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true

        let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let addButton = NSButton(title: "Add", target: nil, action: nil)
        addButton.bezelStyle = .rounded
        addButton.keyEquivalent = "\r"

        let buttonStack = NSStackView(views: [cancelButton, addButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        buttonStack.distribution = .fillEqually

        let stack = NSStackView(views: [titleLabel, subtitleLabel, scrollView, errorLabel, buttonStack])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 104),
            buttonStack.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        super.init()
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        addButton.target = self
        addButton.action = #selector(add)
        position(anchorScreenRect: anchorScreenRect)
    }

    func run() -> String? {
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
        _ = withExtendedLifetime(self) {
            NSApp.runModal(for: panel)
        }
        panel.orderOut(nil)
        return result
    }

    @objc private func add() {
        let comment = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !comment.isEmpty else {
            errorLabel.isHidden = false
            NSSound.beep()
            return
        }
        result = textView.string
        NSApp.stopModal()
    }

    @objc private func cancel() {
        result = nil
        NSApp.stopModal()
    }

    private func position(anchorScreenRect: NSRect?) {
        guard let screen = (anchorScreenRect.flatMap { screen(containing: $0) } ?? NSScreen.main) else {
            panel.center()
            return
        }

        let visible = screen.visibleFrame
        let size = panel.frame.size
        var origin: NSPoint

        if let anchor = anchorScreenRect {
            let belowY = anchor.minY - size.height - 10
            let aboveY = anchor.maxY + 10
            origin = NSPoint(x: anchor.midX - size.width / 2, y: belowY >= visible.minY ? belowY : aboveY)
        } else if let window = NSApp.keyWindow {
            origin = NSPoint(x: window.frame.midX - size.width / 2, y: window.frame.midY - size.height / 2)
        } else {
            origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        }

        origin.x = min(max(origin.x, visible.minX + 12), visible.maxX - size.width - 12)
        origin.y = min(max(origin.y, visible.minY + 12), visible.maxY - size.height - 12)
        panel.setFrameOrigin(origin)
    }

    private func screen(containing rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.visibleFrame.intersects(rect) }
    }
}

enum PreviewAnnotationMapper {
    enum Error: LocalizedError {
        case emptySelection
        case notFound
        case ambiguous

        var errorDescription: String? {
            switch self {
            case .emptySelection:
                return "Select text before adding an annotation."
            case .notFound:
                return "The preview selection could not be matched back to the markdown source. Switch to the editor to annotate this selection."
            case .ambiguous:
                return "That selected text appears more than once in the markdown source. Switch to the editor to annotate the exact occurrence."
            }
        }
    }

    static func sourceRange(for selectedText: String, in markdown: String) throws -> Range<String.Index> {
        let needle = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else {
            throw Error.emptySelection
        }

        let ranges = markdown.ranges(of: needle)
        guard !ranges.isEmpty else {
            throw Error.notFound
        }
        guard ranges.count == 1 else {
            throw Error.ambiguous
        }
        return ranges[0]
    }
}

@MainActor
func performAddAnnotationCommand() {
    if LiveEditorCommandDispatcher.isActive {
        LiveEditorCommandDispatcher.send(.addAnnotation)
    } else if WorkspaceManager.shared.currentViewMode == .preview {
        NotificationCenter.default.post(name: .previewAnnotationCommand, object: nil)
    } else {
        NSApp.sendAction(#selector(ClearlyTextView.addAnnotation(_:)), to: nil, from: nil)
    }
}

private extension String {
    func ranges(of needle: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = startIndex

        while searchStart < endIndex,
              let range = self[searchStart...].range(of: needle) {
            ranges.append(range)
            searchStart = range.upperBound
        }

        return ranges
    }
}
