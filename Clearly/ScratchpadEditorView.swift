import SwiftUI
import AppKit

final class ScratchpadTextView: PersistentTextCheckingTextView {
    var onSave: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        if event.charactersIgnoringModifiers == "s" {
            onSave?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct ScratchpadEditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 16
    var onSave: (() -> Void)?
    @AppStorage(TypographyPreferences.editorFontNameKey) private var editorFontName = ""
    @Environment(\.colorScheme) private var colorScheme

    private var resolvedEditorTypography: EditorTypography {
        TypographyPreferences.editorTypography(size: fontSize, storedFontName: editorFontName.isEmpty ? nil : editorFontName)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let textView = ScratchpadTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.usesFontPanel = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        TextCheckingPreferences.apply(to: textView)

        let editorTypography = resolvedEditorTypography

        textView.font = editorTypography.font
        textView.textColor = Theme.textColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.defaultParagraphStyle = editorTypography.paragraphStyle
        textView.typingAttributes = editorTypography.typingAttributes

        textView.textContainerInset = NSSize(width: 20, height: 8)
        textView.textContainer?.lineFragmentPadding = 0

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.layoutManager?.allowsNonContiguousLayout = true

        textView.insertionPointColor = Theme.textColor

        let highlighter = MarkdownSyntaxHighlighter()
        context.coordinator.highlighter = highlighter
        textView.string = text
        textView.delegate = context.coordinator

        let coordinator = context.coordinator
        textView.onSave = { [weak coordinator] in
            coordinator?.onSave?()
        }
        coordinator.onSave = onSave

        scrollView.documentView = textView
        coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        context.coordinator.parent = self
        context.coordinator.onSave = onSave

        textView.insertionPointColor = Theme.textColor

        let currentScheme = colorScheme
        let currentFontSize = fontSize
        let currentEditorFontName = editorFontName
        let appearanceChanged = context.coordinator.lastColorScheme != currentScheme ||
            context.coordinator.lastFontSize != currentFontSize ||
            context.coordinator.lastEditorFontName != currentEditorFontName
        if appearanceChanged {
            context.coordinator.lastColorScheme = currentScheme
            context.coordinator.lastFontSize = currentFontSize
            context.coordinator.lastEditorFontName = currentEditorFontName

            let editorTypography = resolvedEditorTypography
            textView.font = editorTypography.font
            textView.textColor = Theme.textColor
            textView.defaultParagraphStyle = editorTypography.paragraphStyle
            textView.typingAttributes = editorTypography.typingAttributes

            context.coordinator.isHighlighting = true
            context.coordinator.highlighter?.highlightAll(textView.textStorage!, typography: editorTypography, caller: "scratchpad-appearance")
            context.coordinator.isHighlighting = false
        }

        if !context.coordinator.isUpdating && textView.string != text {
            context.coordinator.isUpdating = true
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
            context.coordinator.isHighlighting = true
            context.coordinator.highlighter?.highlightAll(textView.textStorage!, typography: context.coordinator.currentEditorTypography, caller: "scratchpad-externalText")
            context.coordinator.isHighlighting = false
            context.coordinator.isUpdating = false
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScratchpadEditorView
        var isUpdating = false
        var isHighlighting = false
        var highlighter: MarkdownSyntaxHighlighter?
        weak var textView: NSTextView?
        var lastColorScheme: ColorScheme?
        var lastFontSize: CGFloat?
        var lastEditorFontName = ""
        var onSave: (() -> Void)?

        init(_ parent: ScratchpadEditorView) {
            self.parent = parent
        }

        var currentEditorTypography: EditorTypography {
            TypographyPreferences.editorTypography(size: parent.fontSize, storedFontName: parent.editorFontName.isEmpty ? nil : parent.editorFontName)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if isUpdating { return }

            isHighlighting = true
            highlighter?.highlightAll(textView.textStorage!, typography: currentEditorTypography, caller: "scratchpad-textDidChange")
            isHighlighting = false

            let newText = textView.string
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isUpdating = true
                self.parent.text = newText
                self.isUpdating = false
            }
        }
    }
}
