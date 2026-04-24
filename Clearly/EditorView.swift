import SwiftUI
import ClearlyCore
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
    var extraTopInset: CGFloat = 0
    var showLineNumbers: Bool = false
    var jumpToLineState: JumpToLineState?
    var needsTrafficLightClearance: Bool = false
    var contentWidthEm: CGFloat? = nil
    @Environment(\.colorScheme) private var colorScheme

    private static func computeHorizontalInset(
        scrollViewWidth: CGFloat, contentWidthEm: CGFloat?,
        fontSize: CGFloat, needsTrafficLightClearance: Bool
    ) -> CGFloat {
        let minInset = Theme.editorInsetX + (needsTrafficLightClearance ? 20 : 0)
        guard let emValue = contentWidthEm else { return minInset }
        let maxWidthPoints = emValue * fontSize
        return max(minInset, (scrollViewWidth - maxWidthPoints) / 2.0)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
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
        textView.usesFontPanel = false
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
        let horizontalInset = Self.computeHorizontalInset(
            scrollViewWidth: 0, contentWidthEm: contentWidthEm,
            fontSize: fontSize, needsTrafficLightClearance: needsTrafficLightClearance
        )
        textView.textContainerInset = NSSize(width: horizontalInset, height: Theme.editorInsetTop + extraTopInset)
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
        textView.onWikiLinkClicked = { target, heading in
            NotificationCenter.default.post(
                name: .navigateWikiLink, object: nil,
                userInfo: ["target": target, "heading": heading as Any]
            )
        }
        textView.onPasteRequiresSave = {
            let ws = WorkspaceManager.shared
            _ = ws.saveCurrentFile()
            return ws.currentFileURL
        }
        scrollView.documentView = textView

        // Line number gutter (plain NSView, not NSRulerView)
        let gutter = LineNumberGutterView()
        gutter.textView = textView
        gutter.isHidden = !showLineNumbers
        context.coordinator.gutterView = gutter

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

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleHighlightText(_:)),
            name: .highlightTextInEditor,
            object: nil
        )

        // Frame changes (window resize causing rewrap) — trigger gutter redraw
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textViewFrameDidChange(_:)),
            name: NSView.frameDidChangeNotification,
            object: textView
        )

        // Wire jump-to-line
        if let jumpState = jumpToLineState {
            let coord = context.coordinator
            jumpState.onJump = { [weak coord] line in
                coord?.jumpToLine(line)
            }
            jumpState.editorLineInfo = { [weak coord] in
                coord?.currentLineInfo() ?? (1, 1)
            }
        }

        // Container: gutter | scrollView side by side
        let container = NSView()
        container.addSubview(gutter)
        container.addSubview(scrollView)

        // Layout via autoresizing
        gutter.autoresizingMask = [.height]
        scrollView.autoresizingMask = [.width, .height]

        let gutterWidth = showLineNumbers ? gutter.preferredWidth() : 0
        gutter.frame = NSRect(x: 0, y: 0, width: gutterWidth, height: 0)
        scrollView.frame = NSRect(x: gutterWidth, y: 0, width: 0, height: 0)

        DiagnosticLog.log("makeNSView: EditorView ready")
        return container
    }

    static func dismantleNSView(_ container: NSView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        DiagnosticLog.log("dismantleNSView: EditorView torn down")
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let scrollView = container.subviews.first(where: { $0 is NSScrollView }) as? NSScrollView,
              let textView = scrollView.documentView as? ClearlyTextView else { return }
        let gutter = container.subviews.first(where: { $0 is LineNumberGutterView }) as? LineNumberGutterView

        // Keep coordinator's parent fresh so the binding never goes stale
        context.coordinator.parent = self

        // Toggle line number gutter visibility
        if let gutter {
            let gutterWidth = showLineNumbers ? gutter.preferredWidth() : 0
            if gutter.isHidden == showLineNumbers {
                gutter.isHidden = !showLineNumbers
            }
            let expectedGutterWidth = showLineNumbers ? gutterWidth : 0
            if abs(gutter.frame.width - expectedGutterWidth) > 0.5 || abs(scrollView.frame.minX - expectedGutterWidth) > 0.5 {
                gutter.frame = NSRect(x: 0, y: 0, width: expectedGutterWidth, height: container.bounds.height)
                scrollView.frame = NSRect(x: expectedGutterWidth, y: 0, width: container.bounds.width - expectedGutterWidth, height: container.bounds.height)
            }
        }

        // Update insets (content width, tab bar, traffic light clearance)
        context.coordinator.contentWidthEm = contentWidthEm
        context.coordinator.cachedFontSize = fontSize
        context.coordinator.cachedNeedsTrafficLightClearance = needsTrafficLightClearance
        let horizontalInset = Self.computeHorizontalInset(
            scrollViewWidth: scrollView.frame.width, contentWidthEm: contentWidthEm,
            fontSize: fontSize, needsTrafficLightClearance: needsTrafficLightClearance
        )
        let expectedInset = NSSize(width: horizontalInset, height: Theme.editorInsetTop + extraTopInset)
        if textView.textContainerInset != expectedInset {
            textView.textContainerInset = expectedInset
        }

        let didChangeDocument = context.coordinator.lastPositionSyncID != positionSyncID
        context.coordinator.lastPositionSyncID = positionSyncID

        // Restore scroll + focus when editing becomes visible or the document changes.
        if didChangeDocument {
            context.coordinator.cancelPendingBindingUpdate()
        }

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

            // Refresh ruler when appearance/font changes
            context.coordinator.gutterView?.appearanceDidChange()
        }

        // Only update text if it changed externally (not from user typing).
        // When the user types, textDidChange increments pendingBindingUpdates
        // synchronously, then the async block decrements it after updating the
        // binding. While updates are pending, the text view is authoritative —
        // any mismatch is just the binding lagging behind, not an external change.
        let textMismatch = text.count != textView.string.count || textView.string != text
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
            context.coordinator.gutterView?.textDidChange()
            context.coordinator.gutterView?.selectionDidChange(selectedRange: textView.selectedRange())
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
        weak var textView: ClearlyTextView?
        weak var gutterView: LineNumberGutterView?
        var lastMode: ViewMode?
        var lastPositionSyncID: String?
        var findState: FindState?
        var outlineState: OutlineState?
        var lastColorScheme: ColorScheme?
        var lastFontSize: CGFloat?
        var contentWidthEm: CGFloat?
        var cachedFontSize: CGFloat = 12
        var cachedNeedsTrafficLightClearance: Bool = false
        var updateCount = 0
        private var lastScrollTime: TimeInterval = 0
        private var editGeneration: UInt = 0
        /// Tracks how many async binding updates are in-flight. While > 0,
        /// updateNSView must not replace the text view's content — the text
        /// view is authoritative and the binding will catch up.
        var pendingBindingUpdates = 0
        var pendingBindingUpdateToken: UUID?
        private var pendingFullHighlightWork: DispatchWorkItem?

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

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            gutterView?.selectionDidChange(selectedRange: textView.selectedRange())

            // Store current selection for highlight-on-mode-switch
            let range = textView.selectedRange()
            if range.length > 0 {
                let text = (textView.string as NSString).substring(with: range)
                SelectionBridge.setSelection(text, for: parent.positionSyncID)
            } else {
                SelectionBridge.setSelection(nil, for: parent.positionSyncID)
            }
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

        @objc func handleHighlightText(_ notification: Notification) {
            guard let searchText = notification.userInfo?["text"] as? String,
                  !searchText.isEmpty,
                  let textView else { return }
            let nsText = textView.string as NSString
            guard nsText.length > 0 else { return }

            // Determine visible character range to prioritize matches near current viewport
            var searchStart = 0
            if let layoutManager = textView.layoutManager, let container = textView.textContainer {
                let glyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: container)
                let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
                searchStart = charRange.location
            }

            // Search forward from visible start, then wrap around
            var foundRange = nsText.range(of: searchText, options: [], range: NSRange(location: searchStart, length: nsText.length - searchStart))
            if foundRange.location == NSNotFound {
                foundRange = nsText.range(of: searchText, options: [], range: NSRange(location: 0, length: min(searchStart + searchText.count, nsText.length)))
            }
            guard foundRange.location != NSNotFound else { return }
            textView.scrollRangeToVisible(foundRange)
            textView.showFindIndicator(for: foundRange)
        }

        @objc func flushEditorBuffer(_ notification: Notification) {
            guard let textView else { return }
            commitTextViewContents(textView)
        }

        @objc func textViewFrameDidChange(_ notification: Notification) {
            gutterView?.scrollOrFrameDidChange()

            // Recalculate horizontal inset on window resize to keep text centered
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            let horizontalInset = EditorView.computeHorizontalInset(
                scrollViewWidth: scrollView.frame.width,
                contentWidthEm: contentWidthEm,
                fontSize: cachedFontSize,
                needsTrafficLightClearance: cachedNeedsTrafficLightClearance
            )
            let currentVertical = textView.textContainerInset.height
            let newInset = NSSize(width: horizontalInset, height: currentVertical)
            if abs(textView.textContainerInset.width - newInset.width) > 0.5 {
                textView.textContainerInset = newInset
            }
        }

        func jumpToLine(_ line: Int) {
            guard let textView, line > 0 else { return }
            let text = textView.string
            let lines = (text as NSString).components(separatedBy: "\n")
            let targetLine = min(line, lines.count)
            var charOffset = 0
            for i in 0..<(targetLine - 1) {
                charOffset += (lines[i] as NSString).length + 1
            }
            let nsText = text as NSString
            let location = min(charOffset, nsText.length)
            let range = NSRange(location: location, length: 0)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            if targetLine - 1 < lines.count {
                let lineLen = (lines[targetLine - 1] as NSString).length
                let highlightRange = NSRange(location: location, length: min(lineLen, nsText.length - location))
                textView.showFindIndicator(for: highlightRange)
            }
        }

        func currentLineInfo() -> (current: Int, total: Int) {
            guard let textView else { return (1, 1) }
            let text = textView.string as NSString
            let location = min(textView.selectedRange().location, text.length)
            var lineNumber = 1
            var i = 0
            while i < location {
                if text.character(at: i) == 0x0A { lineNumber += 1 }
                i += 1
            }
            let totalLines = text.components(separatedBy: "\n").count
            return (lineNumber, totalLines)
        }

        func cancelPendingBindingUpdate() {
            pendingBindingUpdates = 0
            pendingBindingUpdateToken = nil
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

        var lastReplacementString: String?

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            lastEditedRange = affectedCharRange
            lastReplacementLength = replacementString?.utf16.count ?? 0
            lastReplacementString = replacementString
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            // Skip if we're the ones setting text programmatically (from updateNSView)
            if isUpdating {
                DiagnosticLog.log("textDidChange skipped (isUpdating)")
                return
            }

            DiagnosticLog.log("textDidChange (\(textView.textStorage?.length ?? 0) chars)")

            // Block updateNSView from replacing text while binding update is pending.
            // Without this, SwiftUI can call updateNSView (e.g., from a layout pass
            // triggered by the text view growing) BEFORE the async binding update fires,
            // see a mismatch between the old binding and the new text, and overwrite
            // the text view with the stale binding value — causing the cursor to jump.
            pendingBindingUpdates = 1

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

            // If a block delimiter was edited, defer the full re-highlight so it
            // doesn't block typing. The paragraph was already highlighted above.
            if highlighter?.needsFullHighlight == true {
                highlighter?.needsFullHighlight = false
                pendingFullHighlightWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self, let textView = self.textView else { return }
                    let sv = textView.enclosingScrollView
                    let origin = sv?.contentView.bounds.origin
                    self.isHighlightingInProgress = true
                    self.highlighter?.highlightAll(textView.textStorage!, caller: "deferred-blockDelim")
                    self.isHighlightingInProgress = false
                    if let sv, let origin {
                        sv.contentView.scroll(to: origin)
                        sv.reflectScrolledClipView(sv.contentView)
                    }
                    self.restoreFindHighlightsIfNeeded()
                }
                pendingFullHighlightWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            }

            // Restore scroll position that highlighting may have disturbed
            if let scrollView, let savedOrigin {
                scrollView.contentView.scroll(to: savedOrigin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }

            // Re-apply find highlights after syntax highlighting
            restoreFindHighlightsIfNeeded()

            // Update line number ruler
            gutterView?.textDidChange()

            // Wiki-link auto-complete trigger/update
            handleWikiLinkCompletion(textView)

            // Update SwiftUI binding with a short debounce. The text view already shows
            // the correct content — the binding is only needed for preview, file saving,
            // and outline parsing, which are expensive on long documents and don't need
            // to run on every keystroke.
            editGeneration += 1
            let gen = editGeneration
            let token = UUID()
            pendingBindingUpdateToken = token
            let scheduledPositionSyncID = lastPositionSyncID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self else { return }
                guard self.pendingBindingUpdateToken == token else { return }
                self.pendingBindingUpdateToken = nil
                self.pendingBindingUpdates = 0
                guard gen == self.editGeneration else { return }
                guard self.lastPositionSyncID == scheduledPositionSyncID else { return }
                guard let textView = self.textView else { return }
                self.commitTextViewContents(textView)
            }
        }

        private func commitTextViewContents(_ textView: NSTextView) {
            parent.text = textView.string
            WorkspaceManager.shared.contentDidChange()
        }

        // MARK: - Wiki-Link Auto-Complete

        private func handleWikiLinkCompletion(_ textView: NSTextView) {
            let completion = WikiLinkCompletionManager.shared

            if completion.isVisible {
                let cursorLocation = textView.selectedRange().location

                // Dismiss if cursor moved before the trigger
                guard cursorLocation >= completion.triggerLocation + 2 else {
                    completion.dismiss()
                    return
                }

                let queryStart = completion.triggerLocation + 2
                let queryLength = cursorLocation - queryStart

                guard queryLength >= 0 else {
                    completion.dismiss()
                    return
                }

                let nsText = textView.string as NSString

                // Check if `]]` was typed
                if cursorLocation >= 2 {
                    let lastTwo = nsText.substring(with: NSRange(location: cursorLocation - 2, length: 2))
                    if lastTwo == "]]" {
                        completion.dismiss()
                        return
                    }
                }

                let query: String
                if queryLength == 0 {
                    query = ""
                } else {
                    query = nsText.substring(with: NSRange(location: queryStart, length: queryLength))
                }

                if query.contains("\n") {
                    completion.dismiss()
                    return
                }

                completion.updateResults(query: query)
                return
            }

            // Not visible — check if `[[` was just typed
            guard let replacement = lastReplacementString, replacement.contains("[") else { return }

            let cursorLocation = textView.selectedRange().location
            guard cursorLocation >= 2 else { return }

            let nsText = textView.string as NSString
            let twoBack = nsText.substring(with: NSRange(location: cursorLocation - 2, length: 2))
            guard twoBack == "[[" else { return }

            // Don't trigger inside code blocks / math / frontmatter
            if highlighter?.isInsideProtectedRange(at: cursorLocation - 2) == true { return }

            completion.show(for: textView, triggerLocation: cursorLocation - 2)
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
            let fraction = min(max(clipView.bounds.origin.y / maxScroll, 0), 1)
            ScrollBridge.setFraction(fraction, for: parent.positionSyncID)

            gutterView?.scrollOrFrameDidChange()
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

            let ranges = TextMatcher.ranges(of: query, in: textView.string)
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
