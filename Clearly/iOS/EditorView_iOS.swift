import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ClearlyCore

/// Writable iOS markdown editor. Binding writes back inside
/// `textViewDidChange` so the parent (typically `IOSDocumentSession.text`)
/// sees every keystroke. The `pendingBindingUpdates` token counter guards
/// `updateUIView` from clobbering the text view during the async SwiftUI
/// state-propagation window. Pattern mirrors the Mac `EditorView`.
struct EditorView_iOS: UIViewRepresentable {

    @Binding var text: String
    var documentURL: URL? = nil
    var outlineState: OutlineState? = nil
    var findState: FindState? = nil

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> ClearlyUITextView {
        let textView = ClearlyUITextView()
        textView.delegate = context.coordinator
        textView.documentURL = documentURL
        textView.addInteraction(UIDropInteraction(delegate: context.coordinator))
        context.coordinator.textView = textView
        context.coordinator.applyExternalText(text)
        context.coordinator.attachOutlineState(outlineState)
        context.coordinator.attachFindState(findState)
        // Auto-focus on mount when the document is empty — matches Notes.app
        // where a fresh note drops you straight into typing. Existing notes
        // with content stay un-focused so the user can read/scroll without
        // the keyboard popping up. The async hop is required because the
        // text view isn't in the window hierarchy yet during `makeUIView`.
        if text.isEmpty {
            DispatchQueue.main.async { [weak textView] in
                textView?.becomeFirstResponder()
            }
        }
        return textView
    }

    func updateUIView(_ textView: ClearlyUITextView, context: Context) {
        context.coordinator.parent = self
        textView.documentURL = documentURL
        context.coordinator.attachOutlineState(outlineState)
        context.coordinator.attachFindState(findState)
        guard context.coordinator.pendingBindingUpdates == 0 else { return }
        guard text != context.coordinator.lastAppliedText else { return }
        context.coordinator.applyExternalText(text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {

        var parent: EditorView_iOS
        weak var textView: ClearlyUITextView?
        let highlighter = MarkdownSyntaxHighlighter()

        var pendingBindingUpdates = 0
        private var pendingBindingUpdateToken: UUID?
        private var isHighlighting = false
        private var lastEditedRange: NSRange?
        private var lastReplacementLength: Int = 0
        private(set) var lastAppliedText: String = ""
        private var pendingFullHighlightWork: DispatchWorkItem?
        private weak var attachedOutlineState: OutlineState?
        private weak var attachedFindState: FindState?
        private var lastFindQuery: String = ""
        private var lastFindVisible: Bool = false
        private var lastFindOptions: TextMatchOptions = TextMatchOptions()
        private var matchRanges: [NSRange] = []
        private var lastMatches: [TextMatch] = []
        private var currentMatchIdx: Int = 0

        init(parent: EditorView_iOS) {
            self.parent = parent
        }

        /// Ownership note: `OutlineState.scrollToRange` is a property the state
        /// holds for whichever editor is currently active. We re-assign it on
        /// every `updateUIView` pass when the state reference changes so the
        /// closure always targets the live text view.
        func attachOutlineState(_ state: OutlineState?) {
            guard attachedOutlineState !== state else { return }
            attachedOutlineState = state
            state?.scrollToRange = { [weak self] range in
                self?.scrollToRange(range)
            }
        }

        /// Wires the FindState's editor-mode navigation callbacks to the
        /// coordinator and re-runs the search when the query/visibility
        /// changes between SwiftUI update passes.
        func attachFindState(_ state: FindState?) {
            if attachedFindState !== state {
                attachedFindState = state
                state?.editorNavigateToNext = { [weak self] in self?.navigateToNextMatch() }
                state?.editorNavigateToPrevious = { [weak self] in self?.navigateToPreviousMatch() }
                state?.editorPerformReplace = { [weak self] in self?.performReplaceCurrent() }
                state?.editorPerformReplaceAll = { [weak self] in self?.performReplaceAll() }
            }
            guard let state else {
                if lastFindVisible {
                    clearFindHighlights()
                    lastFindVisible = false
                    lastFindQuery = ""
                }
                return
            }
            if !state.isVisible {
                if lastFindVisible {
                    clearFindHighlights()
                }
                lastFindVisible = false
                lastFindQuery = ""
                return
            }
            let currentOptions = TextMatchOptions(
                caseSensitive: state.caseSensitive,
                useRegex: state.useRegex
            )
            if !lastFindVisible || state.query != lastFindQuery || currentOptions != lastFindOptions {
                lastFindVisible = true
                lastFindQuery = state.query
                lastFindOptions = currentOptions
                performFind(for: state)
            }
        }

        private func performFind(for state: FindState) {
            guard let textView else { return }
            guard recomputeMatches(for: state) else { return }
            applyFindHighlights()
            if let first = matchRanges.first {
                textView.scrollRangeToVisible(first)
            }
        }

        /// Recomputes matches without painting highlights or scrolling.
        /// Returns false on empty/error so the caller can short-circuit.
        @discardableResult
        private func recomputeMatches(for state: FindState) -> Bool {
            guard let textView else { return false }
            let options = TextMatchOptions(
                caseSensitive: state.caseSensitive,
                useRegex: state.useRegex
            )

            let matches: [TextMatch]
            do {
                matches = try TextMatcher.matches(of: state.query, in: textView.text ?? "", options: options)
            } catch let TextMatcherError.invalidRegex(message) {
                matchRanges = []
                lastMatches = []
                currentMatchIdx = 0
                clearFindHighlights()
                DispatchQueue.main.async { [weak state] in
                    guard let state, state.activeMode == .edit else { return }
                    state.matchCount = 0
                    state.currentIndex = 0
                    state.resultsAreStale = false
                    state.regexError = message
                    state.lastReplaceCount = nil
                }
                return false
            } catch {
                matches = []
            }

            matchRanges = matches.map(\.range)
            lastMatches = matches
            currentMatchIdx = 0

            DispatchQueue.main.async { [weak state] in
                guard let state, state.activeMode == .edit else { return }
                state.matchCount = matches.count
                state.currentIndex = matches.isEmpty ? 0 : 1
                state.resultsAreStale = false
                state.regexError = nil
                state.lastReplaceCount = nil
            }
            return true
        }

        private func navigateToNextMatch() {
            // After clear-on-edit, matchRanges is empty but the query is still
            // in the find bar — treat Next as a re-run trigger.
            if matchRanges.isEmpty, let state = attachedFindState, !state.query.isEmpty {
                performFind(for: state)
                return
            }
            guard !matchRanges.isEmpty else { return }
            currentMatchIdx = (currentMatchIdx + 1) % matchRanges.count
            applyFindHighlights()
            textView?.scrollRangeToVisible(matchRanges[currentMatchIdx])
            let idx = currentMatchIdx
            DispatchQueue.main.async { [weak self] in
                guard let self, let state = self.attachedFindState, state.activeMode == .edit else { return }
                state.currentIndex = idx + 1
            }
        }

        private func navigateToPreviousMatch() {
            if matchRanges.isEmpty, let state = attachedFindState, !state.query.isEmpty {
                performFind(for: state)
                return
            }
            guard !matchRanges.isEmpty else { return }
            currentMatchIdx = (currentMatchIdx - 1 + matchRanges.count) % matchRanges.count
            applyFindHighlights()
            textView?.scrollRangeToVisible(matchRanges[currentMatchIdx])
            let idx = currentMatchIdx
            DispatchQueue.main.async { [weak self] in
                guard let self, let state = self.attachedFindState, state.activeMode == .edit else { return }
                state.currentIndex = idx + 1
            }
        }

        // UIKit's NSLayoutManager has no temporary-attribute API, so find
        // highlights have to use storage attributes. To prevent find color
        // from clobbering `==highlight==` markdown backgrounds, we re-run
        // the syntax highlighter (which resets bg per paragraph) before
        // every paint — and again on clear so dismissed find never leaves
        // missing backgrounds behind.
        private func applyFindHighlights() {
            guard let textView else { return }
            let storage = textView.textStorage
            resetBackgroundsThenRehighlight(storage: storage)
            storage.beginEditing()
            for (i, range) in matchRanges.enumerated() {
                guard range.upperBound <= storage.length else { continue }
                let color = (i == currentMatchIdx) ? Theme.findCurrentHighlightColor : Theme.findHighlightColor
                storage.addAttribute(.backgroundColor, value: color, range: range)
            }
            storage.endEditing()
        }

        private func clearFindHighlights() {
            guard let textView else { return }
            resetBackgroundsThenRehighlight(storage: textView.textStorage)
            matchRanges = []
            lastMatches = []
            currentMatchIdx = 0
        }

        /// Wipe every `.backgroundColor` attribute, then re-run the syntax
        /// highlighter so `==highlight==` markdown backgrounds get repainted.
        /// Without the explicit wipe, find paints from previous queries (e.g.
        /// the partial matches on each keystroke) stay attached to text storage
        /// since the highlighter only adds attributes, never clears them.
        private func resetBackgroundsThenRehighlight(storage: NSTextStorage) {
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: fullRange)
            storage.endEditing()
            rerunSyntaxHighlighter(on: storage)
        }

        // MARK: - Replace

        private func performReplaceCurrent() {
            guard let textView, let state = attachedFindState,
                  !lastMatches.isEmpty,
                  currentMatchIdx < lastMatches.count else { return }
            let match = lastMatches[currentMatchIdx]
            let oldText = textView.text ?? ""
            let nsText = oldText as NSString
            guard match.range.upperBound <= nsText.length else { return }
            let replacement = ReplaceEngine.substitution(for: match,
                                                         in: oldText,
                                                         template: state.replacementText,
                                                         isRegex: state.useRegex)
            let resumeLocation = match.range.location + (replacement as NSString).length
            applyTextReplacement(in: textView, fullOldText: oldText,
                                 replaceRange: match.range,
                                 replacement: replacement,
                                 actionName: "Replace")
            // Silent rescan against the now-updated text, then highlight + scroll
            // to the first remaining match at-or-after the replacement end. Skips
            // any match the replacement string itself may have introduced and
            // avoids the double-paint that calling performFind would cause.
            recomputeMatches(for: state)
            guard !lastMatches.isEmpty else { return }
            currentMatchIdx = lastMatches.firstIndex(where: { $0.range.location >= resumeLocation }) ?? 0
            applyFindHighlights()
            textView.scrollRangeToVisible(matchRanges[currentMatchIdx])
            let idx = currentMatchIdx
            DispatchQueue.main.async { [weak state] in
                guard let state, state.activeMode == .edit else { return }
                state.currentIndex = idx + 1
            }
        }

        private func performReplaceAll() {
            guard let textView, let state = attachedFindState, !lastMatches.isEmpty else { return }
            let oldText = textView.text ?? ""
            let nsOldText = oldText as NSString
            let newText = ReplaceEngine.applyAll(matches: lastMatches,
                                                 in: oldText,
                                                 template: state.replacementText,
                                                 isRegex: state.useRegex)
            let fullRange = NSRange(location: 0, length: nsOldText.length)
            let replaceCount = lastMatches.count
            applyTextReplacement(in: textView, fullOldText: oldText,
                                 replaceRange: fullRange,
                                 replacement: newText,
                                 actionName: "Replace All")
            DispatchQueue.main.async { [weak state] in
                state?.lastReplaceCount = replaceCount
            }
            // Clear the "Replaced N" label after a beat so it doesn't linger.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak state] in
                if state?.lastReplaceCount == replaceCount {
                    state?.lastReplaceCount = nil
                }
            }
        }

        /// Apply a programmatic edit that's reversible via UndoManager.
        /// Single full-text replace produces one undo step and one
        /// `textViewDidChange` pass that runs the highlighter end-to-end.
        /// The textViewDidChange callback bumps `pendingBindingUpdates` itself,
        /// so this method doesn't need to touch that counter.
        private func applyTextReplacement(in textView: ClearlyUITextView,
                                          fullOldText: String,
                                          replaceRange: NSRange,
                                          replacement: String,
                                          actionName: String) {
            let nsOld = fullOldText as NSString
            let newText = nsOld.replacingCharacters(in: replaceRange, with: replacement)
            let undoManager = textView.undoManager
            undoManager?.beginUndoGrouping()
            undoManager?.registerUndo(withTarget: textView) { [weak self] tv in
                self?.applyUndoneText(in: tv, restoredText: fullOldText)
            }
            undoManager?.setActionName(actionName)
            textView.text = newText
            textView.delegate?.textViewDidChange?(textView)
            undoManager?.endUndoGrouping()
        }

        /// Inverse of `applyTextReplacement` — restores the prior text and
        /// re-registers the redo so the next ⌘⇧Z plays the change back.
        private func applyUndoneText(in textView: UITextView, restoredText: String) {
            guard let ctv = textView as? ClearlyUITextView else { return }
            let currentText = ctv.text ?? ""
            let undoManager = ctv.undoManager
            undoManager?.registerUndo(withTarget: ctv) { [weak self] tv in
                self?.applyUndoneText(in: tv, restoredText: currentText)
            }
            ctv.text = restoredText
            ctv.delegate?.textViewDidChange?(ctv)
        }

        private func rerunSyntaxHighlighter(on storage: NSTextStorage) {
            let wasHighlighting = isHighlighting
            isHighlighting = true
            highlighter.highlightAll(storage, caller: "find-rerun")
            isHighlighting = wasHighlighting
        }

        private func scrollToRange(_ range: NSRange) {
            guard let textView else { return }
            let clamped = NSRange(
                location: min(range.location, textView.textStorage.length),
                length: min(range.length, max(0, textView.textStorage.length - range.location))
            )
            textView.scrollRangeToVisible(clamped)
            let previous = textView.selectedRange
            textView.selectedRange = clamped
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak textView] in
                textView?.selectedRange = previous
            }
        }

        func applyExternalText(_ newText: String) {
            guard let textView else { return }
            isHighlighting = true
            let selectedRange = textView.selectedRange
            textView.text = newText
            highlighter.highlightAll(textView.textStorage, caller: "applyExternal")
            let clamped = NSRange(
                location: min(selectedRange.location, (newText as NSString).length),
                length: 0
            )
            textView.selectedRange = clamped
            isHighlighting = false
            lastAppliedText = newText

            // External text replacement (file load/revert) — old match ranges are stale.
            if !matchRanges.isEmpty || !lastMatches.isEmpty {
                matchRanges = []
                lastMatches = []
                currentMatchIdx = 0
                if let state = attachedFindState, state.isVisible, state.activeMode == .edit {
                    DispatchQueue.main.async { [weak state] in
                        guard let state, state.activeMode == .edit else { return }
                        state.matchCount = 0
                        state.currentIndex = 0
                        state.resultsAreStale = true
                    }
                }
            }
        }

        // MARK: - UITextViewDelegate

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard textView.isEditable else { return false }
            lastEditedRange = range
            lastReplacementLength = (text as NSString).length
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isHighlighting, let ctv = textView as? ClearlyUITextView else { return }

            pendingBindingUpdates = 1

            isHighlighting = true
            if let editedRange = lastEditedRange {
                highlighter.highlightAround(
                    ctv.textStorage,
                    editedRange: editedRange,
                    replacementLength: lastReplacementLength,
                    caller: "textViewDidChange"
                )
                lastEditedRange = nil
            } else {
                highlighter.highlightAll(ctv.textStorage, caller: "textViewDidChange-fallback")
            }
            isHighlighting = false

            if highlighter.needsFullHighlight {
                highlighter.needsFullHighlight = false
                pendingFullHighlightWork?.cancel()
                let work = DispatchWorkItem { [weak self, weak ctv] in
                    guard let self, let ctv else { return }
                    self.isHighlighting = true
                    self.highlighter.highlightAll(ctv.textStorage, caller: "deferred-blockDelim")
                    self.isHighlighting = false
                }
                pendingFullHighlightWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            }

            let newText = ctv.text ?? ""
            lastAppliedText = newText
            parent.text = newText

            // Clear on edit; user retypes the query to refresh (#264).
            if let state = attachedFindState, state.isVisible, !matchRanges.isEmpty {
                clearFindHighlights()
                if state.activeMode == .edit {
                    DispatchQueue.main.async { [weak state] in
                        guard let state, state.activeMode == .edit else { return }
                        state.matchCount = 0
                        state.currentIndex = 0
                        state.resultsAreStale = true
                    }
                }
            }

            let token = UUID()
            pendingBindingUpdateToken = token
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, self.pendingBindingUpdateToken == token else { return }
                self.pendingBindingUpdateToken = nil
                self.pendingBindingUpdates = 0
            }
        }
    }
}

// MARK: - UIDropInteractionDelegate

extension EditorView_iOS.Coordinator: UIDropInteractionDelegate {

    func dropInteraction(_ interaction: UIDropInteraction,
                         canHandle session: any UIDropSession) -> Bool {
        return session.hasItemsConforming(toTypeIdentifiers: [UTType.image.identifier])
    }

    func dropInteraction(_ interaction: UIDropInteraction,
                         sessionDidUpdate session: any UIDropSession) -> UIDropProposal {
        if let textView, let pos = textView.closestPosition(to: session.location(in: textView)) {
            let caret = textView.offset(from: textView.beginningOfDocument, to: pos)
            textView.selectedRange = NSRange(location: caret, length: 0)
        }
        return UIDropProposal(operation: .copy)
    }

    func dropInteraction(_ interaction: UIDropInteraction,
                         performDrop session: any UIDropSession) {
        guard let textView else { return }
        let providers: [NSItemProvider] = session.items
            .map { $0.itemProvider }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        guard !providers.isEmpty else { return }

        // Load all items in parallel, then apply inserts on the main actor in
        // the order items appeared so drop order is preserved.
        Task { @MainActor [weak textView] in
            var datas: [Data?] = Array(repeating: nil, count: providers.count)
            await withTaskGroup(of: (Int, Data?).self) { group in
                for (idx, provider) in providers.enumerated() {
                    group.addTask {
                        let data: Data? = await withCheckedContinuation { cont in
                            provider.loadDataRepresentation(
                                forTypeIdentifier: UTType.image.identifier
                            ) { data, _ in
                                cont.resume(returning: data)
                            }
                        }
                        return (idx, data)
                    }
                }
                for await (idx, data) in group { datas[idx] = data }
            }
            guard let textView else { return }
            for data in datas {
                guard let data else { continue }
                textView.handleDroppedImageData(data)
            }
        }
    }
}
