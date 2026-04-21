import SwiftUI
import UIKit
import ClearlyCore

/// Read-only Phase 5 editor: renders markdown with full syntax highlighting on iOS.
/// `text` is a value (not a `@Binding`) — saves ship in Phase 6. The `pendingBindingUpdates`
/// counter and edit-time highlighting wiring are in place now so Phase 6 can promote
/// the value to a binding without re-architecting.
struct EditorView_iOS: UIViewRepresentable {

    let text: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ClearlyUITextView {
        let textView = ClearlyUITextView()
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.applyInitialText(text)
        return textView
    }

    func updateUIView(_ textView: ClearlyUITextView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.pendingBindingUpdates == 0 else { return }
        guard text != coordinator.lastAppliedText else { return }
        coordinator.applyInitialText(text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {

        weak var textView: ClearlyUITextView?
        let highlighter = MarkdownSyntaxHighlighter()

        /// Counter (not a boolean): incremented synchronously in `textViewDidChange`,
        /// decremented in the async block. Guards `updateUIView` from overwriting the
        /// text view while SwiftUI state updates are in flight. Pattern mirrors the Mac
        /// `EditorView`'s `pendingBindingUpdates` in `Clearly/EditorView.swift`.
        var pendingBindingUpdates = 0
        private var pendingBindingUpdateToken: UUID?
        private var isHighlighting = false
        private var lastEditedRange: NSRange?
        private var lastReplacementLength: Int = 0
        private(set) var lastAppliedText: String = ""
        private var pendingFullHighlightWork: DispatchWorkItem?

        func applyInitialText(_ newText: String) {
            guard let textView else { return }
            isHighlighting = true
            let selectedRange = textView.selectedRange
            textView.text = newText
            highlighter.highlightAll(textView.textStorage, caller: "applyInitial")
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
