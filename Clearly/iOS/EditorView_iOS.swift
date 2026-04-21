import SwiftUI
import UIKit
import ClearlyCore

/// Writable iOS markdown editor. Binding writes back inside
/// `textViewDidChange` so the parent (typically `IOSDocumentSession.text`)
/// sees every keystroke. The `pendingBindingUpdates` token counter guards
/// `updateUIView` from clobbering the text view during the async SwiftUI
/// state-propagation window. Pattern mirrors the Mac `EditorView`.
struct EditorView_iOS: UIViewRepresentable {

    @Binding var text: String
    var outlineState: OutlineState? = nil

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> ClearlyUITextView {
        let textView = ClearlyUITextView()
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.applyExternalText(text)
        context.coordinator.attachOutlineState(outlineState)
        return textView
    }

    func updateUIView(_ textView: ClearlyUITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.attachOutlineState(outlineState)
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
