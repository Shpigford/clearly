import SwiftUI
import AppKit
import os

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 16
    var fileURL: URL?
    var scrollSync: ScrollSync?
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        DiagnosticLog.log("makeNSView: creating EditorView (\(text.count) chars)")
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let textView = ClearlyTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        // Font
        textView.font = Theme.editorFont
        textView.textColor = Theme.textColor
        textView.backgroundColor = Theme.backgroundColor

        // Paragraph style with line height — use min/max line height + baselineOffset
        // so text is vertically centered in each line (not top-aligned like lineSpacing)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Theme.editorLineHeight
        paragraph.maximumLineHeight = Theme.editorLineHeight
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: Theme.editorFont,
            .foregroundColor: Theme.textColor,
            .paragraphStyle: paragraph,
            .baselineOffset: Theme.editorBaselineOffset
        ]

        // Insets
        textView.textContainerInset = NSSize(width: Theme.editorInsetX, height: Theme.editorInsetTop)
        textView.textContainer?.lineFragmentPadding = 0

        // Layout
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.layoutManager?.allowsNonContiguousLayout = true

        // Insertion point color
        textView.insertionPointColor = Theme.textColor
        textView.documentURL = fileURL

        // Delegate
        textView.delegate = context.coordinator

        // Set initial text BEFORE attaching the syntax highlighter delegate.
        // This avoids triggering highlightAll during makeNSView — the first
        // updateNSView call handles initial highlighting via the color-scheme check.
        let highlighter = MarkdownSyntaxHighlighter()
        context.coordinator.highlighter = highlighter
        textView.string = text
        textView.textStorage?.delegate = highlighter

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollSync = scrollSync
        scrollSync?.editorScrollView = scrollView

        // Observe scroll position for sync
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        DiagnosticLog.log("makeNSView: EditorView ready")
        return scrollView
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        DiagnosticLog.log("dismantleNSView: EditorView torn down")
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ClearlyTextView else { return }

        // Always refresh colors (handles appearance changes via @Environment colorScheme)
        textView.backgroundColor = Theme.backgroundColor
        textView.insertionPointColor = Theme.textColor
        textView.documentURL = fileURL

        // Update typing attributes for new text
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Theme.editorLineHeight
        paragraph.maximumLineHeight = Theme.editorLineHeight
        textView.typingAttributes = [
            .font: Theme.editorFont,
            .foregroundColor: Theme.textColor,
            .paragraphStyle: paragraph,
            .baselineOffset: Theme.editorBaselineOffset
        ]

        // Re-highlight when appearance or font size changes
        let currentScheme = colorScheme
        let currentFontSize = fontSize
        if context.coordinator.lastColorScheme != currentScheme || context.coordinator.lastFontSize != currentFontSize {
            context.coordinator.lastColorScheme = currentScheme
            context.coordinator.lastFontSize = currentFontSize
            textView.font = Theme.editorFont
            context.coordinator.highlighter?.highlightAll(textView.textStorage!)
        }

        // Only update text if it changed externally (not from user typing).
        // highlightAll fires automatically via NSTextStorageDelegate.
        if !context.coordinator.isUpdating && textView.string != text {
            DiagnosticLog.log("updateNSView: external text change (\(text.count) chars)")
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: EditorView
        var isUpdating = false
        var highlighter: MarkdownSyntaxHighlighter?
        weak var textView: NSTextView?
        var scrollSync: ScrollSync?
        var lastColorScheme: ColorScheme?
        var lastFontSize: CGFloat?
        private var lastScrollTime: TimeInterval = 0

        init(_ parent: EditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isUpdating = true
            parent.text = textView.string
            isUpdating = false
        }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView,
                  let scrollView = clipView.enclosingScrollView,
                  let textView = scrollView.documentView as? NSTextView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            // Throttle to ~60fps
            let now = CACurrentMediaTime()
            guard now - lastScrollTime >= 0.016 else { return }
            lastScrollTime = now

            // Find the character at the CENTER of the visible area
            let centerY = clipView.bounds.origin.y + clipView.bounds.height / 2
            let adjustedY = centerY + textView.textContainerInset.height
            let glyphIndex = layoutManager.glyphIndex(for: NSPoint(x: 0, y: adjustedY), in: textContainer)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

            // Count line number at that character position
            let text = textView.string as NSString
            let safeCharIndex = min(charIndex, text.length)
            var line = 1
            var position = 0
            while position < safeCharIndex {
                let lineRange = text.lineRange(for: NSRange(location: position, length: 0))
                if NSMaxRange(lineRange) > safeCharIndex { break }
                line += 1
                position = NSMaxRange(lineRange)
            }

            // Compute fractional progress within the current line's visual height
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let lineTop = lineRect.origin.y - textView.textContainerInset.height
            let lineHeight = lineRect.height
            let frac = lineHeight > 0 ? min(1, max(0, (centerY - lineTop) / lineHeight)) : 0

            scrollSync?.editorDidScroll(line: Double(line) + frac)
        }
    }
}
