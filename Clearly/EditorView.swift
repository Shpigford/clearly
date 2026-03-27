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

        // Set initial text BEFORE attaching the text view delegate.
        // This avoids triggering textDidChange during makeNSView —
        // the first updateNSView call handles initial highlighting via the color-scheme check.
        // Note: we do NOT set textStorage.delegate — highlighting is driven explicitly
        // from textDidChange and updateNSView to avoid re-entrant layout manager access.
        let highlighter = MarkdownSyntaxHighlighter()
        context.coordinator.highlighter = highlighter
        textView.string = text
        textView.delegate = context.coordinator

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

        // Keep coordinator's parent fresh so the binding never goes stale
        context.coordinator.parent = self

        context.coordinator.updateCount += 1
        let count = context.coordinator.updateCount
        if count <= 5 || count % 100 == 0 {
            DiagnosticLog.log("updateNSView #\(count)")
        }

        // Always refresh colors (handles appearance changes via @Environment colorScheme)
        textView.backgroundColor = Theme.backgroundColor
        textView.insertionPointColor = Theme.textColor
        textView.documentURL = fileURL

        // Re-highlight and update typing attributes when appearance or font size changes
        let currentScheme = colorScheme
        let currentFontSize = fontSize
        let appearanceChanged = context.coordinator.lastColorScheme != currentScheme || context.coordinator.lastFontSize != currentFontSize
        if appearanceChanged {
            if count <= 5 {
                DiagnosticLog.log("updateNSView #\(count): appearance changed (scheme=\(currentScheme), fontSize=\(currentFontSize))")
            }
            context.coordinator.lastColorScheme = currentScheme
            context.coordinator.lastFontSize = currentFontSize
            textView.font = Theme.editorFont

            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = Theme.editorLineHeight
            paragraph.maximumLineHeight = Theme.editorLineHeight
            textView.typingAttributes = [
                .font: Theme.editorFont,
                .foregroundColor: Theme.textColor,
                .paragraphStyle: paragraph,
                .baselineOffset: Theme.editorBaselineOffset
            ]

            // Suppress scroll handler during highlighting to prevent layout manager deadlock
            context.coordinator.isHighlightingInProgress = true
            context.coordinator.highlighter?.highlightAll(textView.textStorage!, caller: "appearance")
            context.coordinator.isHighlightingInProgress = false
        }

        // Only update text if it changed externally (not from user typing).
        let textMismatch = textView.string != text
        if !context.coordinator.isUpdating && textMismatch {
            DiagnosticLog.log("updateNSView #\(count): external text change (\(text.count) chars)")
            context.coordinator.isUpdating = true
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            context.coordinator.isHighlightingInProgress = true
            context.coordinator.highlighter?.highlightAll(textView.textStorage!, caller: "externalText")
            context.coordinator.isHighlightingInProgress = false
            context.coordinator.isUpdating = false
        } else if context.coordinator.isUpdating && count <= 5 {
            DiagnosticLog.log("updateNSView #\(count): skipped text check (isUpdating)")
        }

        if count <= 5 || count % 100 == 0 {
            DiagnosticLog.log("updateNSView #\(count) done")
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorView
        var isUpdating = false
        var isHighlightingInProgress = false
        var highlighter: MarkdownSyntaxHighlighter?
        weak var textView: NSTextView?
        var scrollSync: ScrollSync?
        var lastColorScheme: ColorScheme?
        var lastFontSize: CGFloat?
        var updateCount = 0
        private var lastScrollTime: TimeInterval = 0

        init(_ parent: EditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            // Skip if we're the ones setting text programmatically (from updateNSView)
            if isUpdating {
                DiagnosticLog.log("textDidChange skipped (isUpdating)")
                return
            }

            DiagnosticLog.log("textDidChange (\(textView.string.count) chars)")

            // Highlight synchronously so colors appear on the same frame as the keystroke
            isHighlightingInProgress = true
            highlighter?.highlightAll(textView.textStorage!, caller: "textDidChange")
            isHighlightingInProgress = false

            // Update SwiftUI binding asynchronously to prevent re-entrant updateNSView
            let newText = textView.string
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    DiagnosticLog.log("textDidChange async: coordinator deallocated")
                    return
                }
                DiagnosticLog.log("textDidChange async: updating binding (\(newText.count) chars)")
                self.isUpdating = true
                self.parent.text = newText
                self.isUpdating = false
            }
        }

        private var scrollSuppressCount = 0

        @objc func scrollViewDidScroll(_ notification: Notification) {
            // Suppress during highlighting — the layout manager may be mid-update
            // and querying it here would deadlock the main thread
            guard !isHighlightingInProgress else {
                scrollSuppressCount += 1
                // Log first occurrence and every 100th to avoid flooding
                if scrollSuppressCount == 1 || scrollSuppressCount % 100 == 0 {
                    DiagnosticLog.log("scrollViewDidScroll suppressed ×\(scrollSuppressCount)")
                }
                return
            }

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
