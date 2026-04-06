import SwiftUI
import AppKit
import Combine
import os

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 16
    var fileURL: URL?
    var scrollSync: ScrollSync?
    var findState: FindState?
    var outlineState: OutlineState?
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
        textView.usesFindPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        TextCheckingPreferences.apply(to: textView)

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
        textView.layoutManager?.allowsNonContiguousLayout = false

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
        context.coordinator.findState = findState
        context.coordinator.outlineState = outlineState
        if let findState {
            context.coordinator.observeFindState(findState)
        }
        scrollSync?.editorScrollView = scrollView

        // Wire up find bar presentation
        textView.onShowFind = { [weak findState] in
            guard let findState else { return }
            DispatchQueue.main.async {
                findState.present()
            }
        }

        // Wire up find navigation
        let coordinator = context.coordinator
        findState?.navigateToNext = { [weak coordinator] in
            coordinator?.navigateToNextMatch()
        }
        findState?.navigateToPrevious = { [weak coordinator] in
            coordinator?.navigateToPreviousMatch()
        }

        // Wire up outline scroll-to
        outlineState?.scrollToRange = { [weak coordinator] range in
            coordinator?.scrollToHeading(range)
        }

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
            context.coordinator.restoreFindHighlightsIfNeeded()
        }

        // Only update text if it changed externally (not from user typing).
        // When the user types, textDidChange increments pendingBindingUpdates
        // synchronously, then the async block decrements it after updating the
        // binding. While updates are pending, the text view is authoritative —
        // any mismatch is just the binding lagging behind, not an external change.
        let textMismatch = textView.string != text
        if !context.coordinator.isUpdating && context.coordinator.pendingBindingUpdates == 0 && textMismatch {
            DiagnosticLog.log("updateNSView #\(count): external text change (\(text.count) chars)")
            context.coordinator.isUpdating = true
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            context.coordinator.isHighlightingInProgress = true
            context.coordinator.highlighter?.highlightAll(textView.textStorage!, caller: "externalText")
            context.coordinator.isHighlightingInProgress = false
            context.coordinator.restoreFindHighlightsIfNeeded()
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
        var findState: FindState?
        var outlineState: OutlineState?
        var lastColorScheme: ColorScheme?
        var lastFontSize: CGFloat?
        var updateCount = 0
        private var lastScrollTime: TimeInterval = 0
        private var editGeneration: UInt = 0
        /// Tracks how many async binding updates are in-flight. While > 0,
        /// updateNSView must not replace the text view's content — the text
        /// view is authoritative and the binding will catch up.
        var pendingBindingUpdates = 0

        // Find state tracking
        var matchRanges: [NSRange] = []
        private var currentMatchIdx = 0 // 0-based internal index
        private var findCancellables = Set<AnyCancellable>()

        init(_ parent: EditorView) {
            self.parent = parent
        }

        func scrollToHeading(_ range: NSRange) {
            guard let textView else { return }
            textView.scrollRangeToVisible(range)
            textView.showFindIndicator(for: range)
        }

        func observeFindState(_ state: FindState) {
            findCancellables.removeAll()

            state.$query
                .removeDuplicates()
                .sink { [weak self] _ in
                    guard let self, self.findState?.isVisible == true else { return }
                    self.performFind()
                }
                .store(in: &findCancellables)

            state.$isVisible
                .removeDuplicates()
                .sink { [weak self] visible in
                    guard let self else { return }
                    if visible {
                        self.performFind()
                    } else {
                        self.clearFindHighlights()
                    }
                }
                .store(in: &findCancellables)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            // Skip if we're the ones setting text programmatically (from updateNSView)
            if isUpdating {
                DiagnosticLog.log("textDidChange skipped (isUpdating)")
                return
            }

            DiagnosticLog.log("textDidChange (\(textView.string.count) chars)")

            // Block updateNSView from replacing text while binding update is pending.
            // Without this, SwiftUI can call updateNSView (e.g., from a layout pass
            // triggered by the text view growing) BEFORE the async binding update fires,
            // see a mismatch between the old binding and the new text, and overwrite
            // the text view with the stale binding value — causing the cursor to jump.
            pendingBindingUpdates += 1

            // Save scroll position before highlighting
            let scrollView = textView.enclosingScrollView
            let savedOrigin = scrollView?.contentView.bounds.origin

            // Highlight synchronously so colors appear on the same frame as the keystroke
            isHighlightingInProgress = true
            highlighter?.highlightAll(textView.textStorage!, caller: "textDidChange")
            isHighlightingInProgress = false

            // Restore scroll position that highlighting may have disturbed
            if let scrollView, let savedOrigin {
                scrollView.contentView.scroll(to: savedOrigin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }

            // Re-apply find highlights after syntax highlighting
            restoreFindHighlightsIfNeeded()

            // Update SwiftUI binding asynchronously to prevent re-entrant updateNSView.
            // Use a generation counter to coalesce rapid updates.
            editGeneration += 1
            let gen = editGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pendingBindingUpdates -= 1
                guard gen == self.editGeneration else { return }
                guard let textView = self.textView else { return }
                self.parent.text = textView.string
            }
        }

        private var scrollSuppressCount = 0

        @objc func scrollViewDidScroll(_ notification: Notification) {
            // Suppress during highlighting to avoid scheduling unnecessary async blocks
            guard !isHighlightingInProgress else {
                scrollSuppressCount += 1
                if scrollSuppressCount == 1 || scrollSuppressCount % 100 == 0 {
                    DiagnosticLog.log("scrollViewDidScroll suppressed ×\(scrollSuppressCount)")
                }
                return
            }

            guard let clipView = notification.object as? NSClipView else { return }

            // Defer layout manager queries to the next run loop iteration.
            // boundsDidChangeNotification fires synchronously during layout passes;
            // querying the layout manager in that same call stack deadlocks the main thread.
            DispatchQueue.main.async { [weak self] in
                self?.computeScrollPosition(clipView)
            }
        }

        private func computeScrollPosition(_ clipView: NSClipView) {
            guard let scrollView = clipView.enclosingScrollView,
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

        // MARK: - Find

        func restoreFindHighlightsIfNeeded() {
            guard findState?.isVisible == true, !(findState?.query.isEmpty ?? true) else { return }
            // Re-apply cached highlight colors without re-running the full find
            // (which would scroll to the first match on every keystroke).
            guard !matchRanges.isEmpty else { return }
            applyFindHighlights()
        }

        func performFind() {
            guard let textView, let findState else { return }
            let query = findState.query
            clearFindHighlights()

            guard !query.isEmpty else {
                matchRanges = []
                currentMatchIdx = 0
                DispatchQueue.main.async {
                    findState.matchCount = 0
                    findState.currentIndex = 0
                }
                return
            }

            // Find all matches (case-insensitive)
            let nsText = textView.string as NSString
            var ranges: [NSRange] = []
            var searchRange = NSRange(location: 0, length: nsText.length)
            while searchRange.location < nsText.length {
                let found = nsText.range(of: query, options: .caseInsensitive, range: searchRange)
                if found.location == NSNotFound { break }
                ranges.append(found)
                searchRange.location = found.upperBound
                searchRange.length = nsText.length - searchRange.location
            }

            matchRanges = ranges
            currentMatchIdx = ranges.isEmpty ? 0 : 0

            applyFindHighlights()

            DispatchQueue.main.async {
                findState.matchCount = ranges.count
                findState.currentIndex = ranges.isEmpty ? 0 : 1
            }

            if !ranges.isEmpty {
                textView.scrollRangeToVisible(ranges[0])
            }
        }

        func navigateToNextMatch() {
            guard !matchRanges.isEmpty else { return }
            currentMatchIdx = (currentMatchIdx + 1) % matchRanges.count
            applyFindHighlights()
            textView?.scrollRangeToVisible(matchRanges[currentMatchIdx])
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.findState?.currentIndex = self.currentMatchIdx + 1
            }
        }

        func navigateToPreviousMatch() {
            guard !matchRanges.isEmpty else { return }
            currentMatchIdx = (currentMatchIdx - 1 + matchRanges.count) % matchRanges.count
            applyFindHighlights()
            textView?.scrollRangeToVisible(matchRanges[currentMatchIdx])
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.findState?.currentIndex = self.currentMatchIdx + 1
            }
        }

        private func applyFindHighlights() {
            guard let textView else { return }
            let storage = textView.textStorage!

            // Clear existing find highlights first
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: fullRange)

            // Apply highlight to all matches
            for (i, range) in matchRanges.enumerated() {
                guard range.upperBound <= storage.length else { continue }
                let color = (i == currentMatchIdx) ? Theme.findCurrentHighlightColor : Theme.findHighlightColor
                storage.addAttribute(.backgroundColor, value: color, range: range)
            }
            storage.endEditing()
        }

        func clearFindHighlights() {
            guard let textView else { return }
            let storage = textView.textStorage!
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: fullRange)
            storage.endEditing()
            matchRanges = []
            currentMatchIdx = 0
        }
    }
}
