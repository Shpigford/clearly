import SwiftUI
import AppKit
import Combine
import os

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 16
    var fileURL: URL?
    var mode: ViewMode
    var positionSyncID: String
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
        context.coordinator.findState = findState
        context.coordinator.outlineState = outlineState
        if let findState {
            context.coordinator.observeFindState(findState)
        }
        // Wire up find bar presentation
        textView.onShowFind = { [weak findState] in
            guard let findState else { return }
            DispatchQueue.main.async {
                findState.present()
            }
        }

        // Wire up find navigation
        let coordinator = context.coordinator
        findState?.editorNavigateToNext = { [weak coordinator] in
            coordinator?.navigateToNextMatch()
        }
        findState?.editorNavigateToPrevious = { [weak coordinator] in
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

        // Observe click-to-source from preview
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleScrollToLine(_:)),
            name: .scrollEditorToLine,
            object: nil
        )

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.flushEditorBuffer(_:)),
            name: .flushEditorBuffer,
            object: nil
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

        let didChangeDocument = context.coordinator.lastPositionSyncID != positionSyncID
        context.coordinator.lastPositionSyncID = positionSyncID

        // Restore scroll + focus when editing becomes visible or the document changes.
        if mode == .edit && (context.coordinator.lastMode != .edit || didChangeDocument) {
            findState?.activeMode = .edit
            let fraction = ScrollBridge.fraction(for: positionSyncID)
            let docHeight = scrollView.documentView?.frame.height ?? 1
            let viewportHeight = scrollView.contentView.bounds.height
            let maxScroll = max(1, docHeight - viewportHeight)
            scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: fraction * maxScroll))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
            if findState?.isVisible == true {
                context.coordinator.performFind()
            }
        }
        context.coordinator.lastMode = mode

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
        var lastEditedRange: NSRange?
        var lastReplacementLength: Int = 0
        weak var textView: NSTextView?
        var lastMode: ViewMode?
        var lastPositionSyncID: String?
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

        @objc func handleScrollToLine(_ notification: Notification) {
            guard let line = notification.userInfo?["line"] as? Int,
                  let textView,
                  line > 0 else { return }
            let text = textView.string
            let lines = (text as NSString).components(separatedBy: "\n")
            let targetLine = min(line, lines.count)
            var charOffset = 0
            for i in 0..<(targetLine - 1) {
                charOffset += (lines[i] as NSString).length + 1 // +1 for \n
            }
            let nsText = text as NSString
            let range = NSRange(location: min(charOffset, nsText.length), length: 0)
            textView.scrollRangeToVisible(range)
            // Briefly highlight the line
            if targetLine - 1 < lines.count {
                let lineLen = (lines[targetLine - 1] as NSString).length
                let highlightRange = NSRange(location: min(charOffset, nsText.length), length: min(lineLen, nsText.length - charOffset))
                textView.showFindIndicator(for: highlightRange)
            }
        }

        @objc func flushEditorBuffer(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
        }

        func observeFindState(_ state: FindState) {
            findCancellables.removeAll()

            state.$query
                .removeDuplicates()
                .sink { [weak self] _ in
                    guard let self,
                          let findState = self.findState,
                          findState.isVisible,
                          findState.activeMode == .edit else { return }
                    self.performFind()
                }
                .store(in: &findCancellables)

            state.$isVisible
                .removeDuplicates()
                .sink { [weak self] visible in
                    guard let self else { return }
                    if visible {
                        guard self.findState?.activeMode == .edit else { return }
                        self.performFind()
                    } else {
                        self.clearFindHighlights()
                    }
                }
                .store(in: &findCancellables)
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            lastEditedRange = affectedCharRange
            lastReplacementLength = replacementString?.utf16.count ?? 0
            return true
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

            // Highlight only the affected range for performance on long documents
            isHighlightingInProgress = true
            if let editedRange = lastEditedRange {
                highlighter?.highlightAround(textView.textStorage!, editedRange: editedRange, replacementLength: lastReplacementLength, caller: "textDidChange")
                lastEditedRange = nil
            } else {
                highlighter?.highlightAll(textView.textStorage!, caller: "textDidChange-fallback")
            }
            isHighlightingInProgress = false

            // Restore scroll position that highlighting may have disturbed
            if let scrollView, let savedOrigin {
                scrollView.contentView.scroll(to: savedOrigin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }

            // Re-apply find highlights after syntax highlighting
            restoreFindHighlightsIfNeeded()

            // Update SwiftUI binding with a short debounce. The text view already shows
            // the correct content — the binding is only needed for preview, file saving,
            // and outline parsing, which are expensive on long documents and don't need
            // to run on every keystroke.
            editGeneration += 1
            let gen = editGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
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
                self?.computeScrollFraction(clipView)
            }
        }

        private func computeScrollFraction(_ clipView: NSClipView) {
            guard let scrollView = clipView.enclosingScrollView else { return }
            let now = CACurrentMediaTime()
            guard now - lastScrollTime >= 0.016 else { return }
            lastScrollTime = now

            let docHeight = scrollView.documentView?.frame.height ?? 1
            let viewportHeight = clipView.bounds.height
            let maxScroll = max(1, docHeight - viewportHeight)
            ScrollBridge.setFraction(clipView.bounds.origin.y / maxScroll, for: parent.positionSyncID)
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
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          let findState = self.findState,
                          findState.activeMode == .edit else { return }
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

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let findState = self.findState,
                      findState.activeMode == .edit else { return }
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
                guard let self,
                      let findState = self.findState,
                      findState.activeMode == .edit else { return }
                findState.currentIndex = self.currentMatchIdx + 1
            }
        }

        func navigateToPreviousMatch() {
            guard !matchRanges.isEmpty else { return }
            currentMatchIdx = (currentMatchIdx - 1 + matchRanges.count) % matchRanges.count
            applyFindHighlights()
            textView?.scrollRangeToVisible(matchRanges[currentMatchIdx])
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      let findState = self.findState,
                      findState.activeMode == .edit else { return }
                findState.currentIndex = self.currentMatchIdx + 1
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
