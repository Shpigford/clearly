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
        private var matchRanges: [NSRange] = []
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
            if !lastFindVisible || state.query != lastFindQuery {
                lastFindVisible = true
                lastFindQuery = state.query
                performFind(for: state)
            }
        }

        private func performFind(for state: FindState) {
            guard let textView else { return }
            let ranges = TextMatcher.ranges(of: state.query, in: textView.text ?? "")
            matchRanges = ranges
            currentMatchIdx = 0
            applyFindHighlights()

            DispatchQueue.main.async { [weak self, weak state] in
                guard let state, state.activeMode == .edit else { return }
                state.matchCount = ranges.count
                state.currentIndex = ranges.isEmpty ? 0 : 1
                _ = self
            }

            if let first = ranges.first {
                textView.scrollRangeToVisible(first)
            }
        }

        private func navigateToNextMatch() {
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

        private func applyFindHighlights() {
            guard let textView else { return }
            let storage = textView.textStorage
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: fullRange)
            for (i, range) in matchRanges.enumerated() {
                guard range.upperBound <= storage.length else { continue }
                let color = (i == currentMatchIdx) ? Theme.findCurrentHighlightColor : Theme.findHighlightColor
                storage.addAttribute(.backgroundColor, value: color, range: range)
            }
            storage.endEditing()
        }

        private func clearFindHighlights() {
            guard let textView else { return }
            let storage = textView.textStorage
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: fullRange)
            storage.endEditing()
            matchRanges = []
            currentMatchIdx = 0
        }

        /// Called at the tail of `textViewDidChange` so the syntax-highlighter's
        /// attribute rewrite doesn't wipe find backgrounds. Mirrors the Mac
        /// `restoreFindHighlightsIfNeeded` pattern — if the query is still
        /// active, re-run the search so match ranges track the edit too.
        private func restoreFindHighlightsIfNeeded() {
            guard let state = attachedFindState, state.isVisible, !state.query.isEmpty else { return }
            performFind(for: state)
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

            restoreFindHighlightsIfNeeded()

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
