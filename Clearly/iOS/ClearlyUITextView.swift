import UIKit
import ClearlyCore

/// UITextView configured for markdown editing: monospaced typing attributes, editor
/// background/tint, autocorrect/smart-quote disabled, vault-appropriate insets.
/// The highlighter is owned by `EditorView_iOS.Coordinator`, mirroring the Mac pattern
/// where highlighting is driven by the delegate rather than the view.
final class ClearlyUITextView: UITextView {

    init() {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: .zero)
        container.widthTracksTextView = true
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)

        super.init(frame: .zero, textContainer: container)

        backgroundColor = Theme.backgroundColor
        textColor = Theme.textColor
        font = Theme.editorFont
        tintColor = Theme.accentColor
        isEditable = false
        isSelectable = true
        allowsEditingTextAttributes = false
        autocapitalizationType = .none
        autocorrectionType = .no
        smartQuotesType = .no
        smartDashesType = .no
        smartInsertDeleteType = .no
        spellCheckingType = .no
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive

        textContainerInset = UIEdgeInsets(
            top: Theme.editorInsetTop,
            left: 16,
            bottom: Theme.editorInsetBottom,
            right: 16
        )

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Theme.editorLineHeight
        paragraph.maximumLineHeight = Theme.editorLineHeight
        typingAttributes = [
            .font: Theme.editorFont,
            .foregroundColor: Theme.textColor,
            .paragraphStyle: paragraph,
            .baselineOffset: Theme.editorBaselineOffset
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
