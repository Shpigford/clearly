import AppKit
import ClearlyCore

final class LineNumberGutterView: NSView {
    weak var textView: NSTextView?
    private var currentLineIndex: Int = 0 // 0-based

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Width

    func preferredWidth() -> CGFloat {
        guard let textView else { return 36 }
        let lineCount = max(1, (textView.string as NSString).components(separatedBy: "\n").count)
        let digits = max(2, String(lineCount).count)
        let charWidth = NSString(string: "8").size(withAttributes: [.font: Theme.editorFont]).width
        return ceil(CGFloat(digits) * charWidth + 20)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        Theme.backgroundColor.setFill()
        dirtyRect.fill()

        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let text = textView.string as NSString

        // Convert coordinate systems: gutter ↔ text view
        let relativePoint = convert(NSZeroPoint, from: textView)

        guard text.length > 0 else {
            let y = relativePoint.y + textView.textContainerOrigin.y
            drawLineNumber(1, at: y, isCurrent: true)
            return
        }

        guard let scrollView = textView.enclosingScrollView else { return }
        let visibleRect = scrollView.contentView.bounds

        // Visible glyph range
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard visibleGlyphRange.length > 0 else { return }

        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        // Find the logical line number at the start of the visible range
        var lineNumber = 1
        var scanIndex = 0
        let startChar = visibleCharRange.location
        while scanIndex < startChar {
            if text.character(at: scanIndex) == 0x0A {
                lineNumber += 1
            }
            scanIndex += 1
        }

        // Walk back to the start of the first visible logical line
        var lineStart = startChar
        if lineStart > 0 {
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            lineStart = lineRange.location
        }

        let containerOrigin = textView.textContainerOrigin

        // Enumerate logical lines in the visible range
        var charIndex = lineStart
        while charIndex <= NSMaxRange(visibleCharRange) && charIndex <= text.length {
            let lineRange: NSRange
            if charIndex < text.length {
                lineRange = text.lineRange(for: NSRange(location: charIndex, length: 0))
            } else {
                if layoutManager.extraLineFragmentTextContainer != nil {
                    let extraRect = layoutManager.extraLineFragmentRect
                    let y = relativePoint.y + containerOrigin.y + extraRect.origin.y
                    drawLineNumber(lineNumber, at: y, isCurrent: lineNumber - 1 == currentLineIndex)
                }
                break
            }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else {
                charIndex = NSMaxRange(lineRange)
                lineNumber += 1
                continue
            }

            var effectiveRange = NSRange(location: 0, length: 0)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: &effectiveRange, withoutAdditionalLayout: true)

            let y = relativePoint.y + containerOrigin.y + lineRect.origin.y
            drawLineNumber(lineNumber, at: y, isCurrent: lineNumber - 1 == currentLineIndex)

            charIndex = NSMaxRange(lineRange)
            lineNumber += 1
        }
    }

    private func drawLineNumber(_ number: Int, at y: CGFloat, isCurrent: Bool) {
        let font = Theme.editorFont
        let color = isCurrent ? Theme.textColor : Theme.syntaxColor
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        let string = "\(number)" as NSString
        let size = string.size(withAttributes: attrs)

        let x = bounds.width - size.width - 8
        let adjustedY = y + (Theme.editorLineHeight - size.height) / 2

        string.draw(at: NSPoint(x: x, y: adjustedY), withAttributes: attrs)
    }

    // MARK: - Update triggers

    func textDidChange() {
        needsDisplay = true
    }

    func selectionDidChange(selectedRange: NSRange) {
        guard let textView else { return }
        let text = textView.string as NSString
        var line = 0
        var i = 0
        let location = min(selectedRange.location, text.length)
        while i < location {
            if text.character(at: i) == 0x0A { line += 1 }
            i += 1
        }
        if currentLineIndex != line {
            currentLineIndex = line
            needsDisplay = true
        }
    }

    func scrollOrFrameDidChange() {
        needsDisplay = true
    }

    func appearanceDidChange() {
        needsDisplay = true
    }
}
