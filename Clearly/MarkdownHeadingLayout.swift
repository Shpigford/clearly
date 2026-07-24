import AppKit
import ClearlyCore

/// Applies the shared syntax highlighter, then adds the Mac editor's
/// paragraph geometry for hanging ATX heading markers.
final class MarkdownEditorHighlighter {
    private let syntaxHighlighter = MarkdownSyntaxHighlighter()

    var needsFullHighlight: Bool {
        get { syntaxHighlighter.needsFullHighlight }
        set { syntaxHighlighter.needsFullHighlight = newValue }
    }

    func highlightAll(_ textStorage: NSTextStorage, caller: String = "") {
        syntaxHighlighter.highlightAll(textStorage, caller: caller)
        MarkdownHeadingLayout.apply(
            to: textStorage,
            in: NSRange(location: 0, length: textStorage.length),
            syntaxHighlighter: syntaxHighlighter
        )
    }

    func highlightAround(
        _ textStorage: NSTextStorage,
        editedRange: NSRange,
        replacementLength: Int,
        caller: String = ""
    ) {
        syntaxHighlighter.highlightAround(
            textStorage,
            editedRange: editedRange,
            replacementLength: replacementLength,
            caller: caller
        )
        MarkdownHeadingLayout.apply(
            to: textStorage,
            in: MarkdownHeadingLayout.affectedParagraphRange(
                in: textStorage.string,
                editedRange: editedRange,
                replacementLength: replacementLength
            ),
            syntaxHighlighter: syntaxHighlighter
        )
    }
}

enum MarkdownHeadingLayout {
    static func markerWidth(for prefix: String) -> CGFloat {
        (prefix as NSString).size(withAttributes: [.font: Theme.editorFont]).width
    }

    /// AppKit tab stops are absolute, so the tab grid must be re-anchored at
    /// the body-text column after introducing the internal marker gutter.
    static var tabInterval: CGFloat {
        markerWidth(for: "    ")
    }

    /// Fits the widest editable prefix (`###### `) and rounds to the tab grid.
    static var markerGutterWidth: CGFloat {
        ceil(markerWidth(for: "###### ") / tabInterval) * tabInterval
    }

    /// The internal gutter is subtracted from the text container's outer inset,
    /// leaving the visible body-text margin unchanged.
    static func paragraphStyle() -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Theme.editorLineHeight
        paragraph.maximumLineHeight = Theme.editorLineHeight
        paragraph.firstLineHeadIndent = markerGutterWidth
        paragraph.headIndent = markerGutterWidth
        paragraph.tailIndent = -markerGutterWidth
        paragraph.tabStops = []
        paragraph.defaultTabInterval = tabInterval
        return paragraph
    }

    static func containerInset(forContentInset contentInset: CGFloat) -> CGFloat {
        max(0, max(contentInset, markerGutterWidth + 8) - markerGutterWidth)
    }

    static func apply(
        to textStorage: NSTextStorage,
        in requestedRange: NSRange,
        syntaxHighlighter: MarkdownSyntaxHighlighter
    ) {
        guard textStorage.length > 0 else { return }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let range = NSIntersectionRange(requestedRange, fullRange)
        guard range.length > 0 else { return }

        let text = textStorage.string as NSString
        textStorage.beginEditing()
        resetParagraphGeometryIfNeeded(in: range, of: textStorage)

        var location = range.location
        while location < NSMaxRange(range) {
            let lineRange = text.lineRange(
                for: NSRange(location: location, length: 0)
            )
            let styledLineRange = NSIntersectionRange(lineRange, fullRange)
            let line = text.substring(with: styledLineRange)

            if !syntaxHighlighter.isInsideProtectedRange(at: lineRange.location),
               let prefix = ATXHeadingPrefix.parse(in: line) {
                let prefixString = String(prefix)
                let prefixRange = NSRange(
                    location: lineRange.location,
                    length: prefixString.utf16.count
                )
                let headingParagraph = paragraphStyle()
                headingParagraph.firstLineHeadIndent =
                    markerGutterWidth - markerWidth(for: prefixString)

                textStorage.addAttribute(
                    .paragraphStyle,
                    value: headingParagraph,
                    range: styledLineRange
                )
                textStorage.addAttribute(
                    .foregroundColor,
                    value: Theme.syntaxColor,
                    range: prefixRange
                )
            }

            let nextLocation = NSMaxRange(lineRange)
            location = nextLocation > location ? nextLocation : location + 1
        }

        textStorage.endEditing()
    }

    private static func resetParagraphGeometryIfNeeded(
        in range: NSRange,
        of textStorage: NSTextStorage
    ) {
        var needsReset = false
        textStorage.enumerateAttribute(
            .paragraphStyle,
            in: range,
            options: .longestEffectiveRangeNotRequired
        ) { value, _, stop in
            guard let paragraph = value as? NSParagraphStyle,
                  paragraph.firstLineHeadIndent == markerGutterWidth,
                  paragraph.headIndent == markerGutterWidth,
                  paragraph.tailIndent == -markerGutterWidth,
                  paragraph.defaultTabInterval == tabInterval else {
                needsReset = true
                stop.pointee = true
                return
            }
        }

        if needsReset {
            textStorage.addAttribute(
                .paragraphStyle,
                value: paragraphStyle(),
                range: range
            )
        }
    }

    static func affectedParagraphRange(
        in text: String,
        editedRange: NSRange,
        replacementLength: Int
    ) -> NSRange {
        let nsText = text as NSString
        let textLength = nsText.length
        let safeLocation = max(0, min(editedRange.location, textLength))
        let safeLength = max(
            0,
            min(replacementLength, textLength - safeLocation)
        )

        guard safeLocation == editedRange.location,
              safeLength == replacementLength else {
            return NSRange(location: 0, length: textLength)
        }

        let insertedRange = NSRange(
            location: safeLocation,
            length: safeLength
        )
        var paragraphRange = nsText.paragraphRange(for: insertedRange)

        if safeLength > 0,
           nsText.substring(with: insertedRange).contains("\n") {
            let followingLocation = NSMaxRange(paragraphRange)
            if followingLocation < textLength {
                paragraphRange = NSUnionRange(
                    paragraphRange,
                    nsText.paragraphRange(
                        for: NSRange(location: followingLocation, length: 1)
                    )
                )
            }
        }

        return paragraphRange
    }
}

/// Owns the TextKit 1 graph used by both Mac markdown editors.
final class MarkdownTextSystem {
    let textStorage: NSTextStorage
    let layoutManager: MarkdownLayoutManager
    let textContainer: NSTextContainer

    init() {
        textStorage = NSTextStorage()
        layoutManager = MarkdownLayoutManager()
        textContainer = NSTextContainer()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
    }
}

/// Keeps the caret for an empty final paragraph at the body-text column.
final class MarkdownLayoutManager: NSLayoutManager {
    override func setExtraLineFragmentRect(
        _ fragmentRect: NSRect,
        usedRect: NSRect,
        textContainer: NSTextContainer
    ) {
        let bodyIndent = MarkdownHeadingLayout.markerGutterWidth
        var adjustedFragment = fragmentRect
        let fragmentAdjustment = max(0, bodyIndent - adjustedFragment.minX)
        adjustedFragment.origin.x += fragmentAdjustment
        adjustedFragment.size.width = max(
            0,
            adjustedFragment.width - fragmentAdjustment
        )

        let desiredMaxX = max(
            adjustedFragment.minX,
            textContainer.size.width - bodyIndent
        )
        adjustedFragment.size.width = min(
            adjustedFragment.width,
            desiredMaxX - adjustedFragment.minX
        )

        var adjustedUsed = usedRect
        let usedAdjustment = max(0, bodyIndent - adjustedUsed.minX)
        adjustedUsed.origin.x += usedAdjustment
        adjustedUsed.size.width = max(0, adjustedUsed.width - usedAdjustment)

        super.setExtraLineFragmentRect(
            adjustedFragment,
            usedRect: adjustedUsed,
            textContainer: textContainer
        )
    }
}
