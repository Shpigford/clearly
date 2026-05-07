import AppKit
import ClearlyCore

final class LineNumberGutterView: NSView {
    weak var textView: NSTextView?
    private var currentLineIndex: Int = 0 // 0-based
    private var lineStarts: [Int] = [0]
    private var cachedTextLength: Int = 0
    private var lineCacheValid = false

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
        ensureLineCache()
        let lineCount = max(1, lineStarts.count)
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

        ensureLineCache()
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

        let startChar = visibleCharRange.location

        // Walk back to the start of the first visible logical line
        var lineStart = startChar
        if lineStart > 0 {
            let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            lineStart = lineRange.location
        }
        var lineNumber = lineIndex(containing: lineStart) + 1

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

    func reloadData() {
        rebuildLineCache()
        // After a full reload (e.g. external text replacement on document
        // switch), the cached currentLineIndex is for the previous document.
        // Re-derive from the live selection so the highlight lands on the
        // right line until the next selectionDidChange call.
        if let textView {
            currentLineIndex = lineIndex(containing: textView.selectedRange().location)
        }
        needsDisplay = true
    }

    func textDidChange(editedRange: NSRange? = nil, replacementString: String? = nil) {
        guard !isHidden else {
            lineCacheValid = false
            return
        }
        if let editedRange {
            updateLineCache(editedRange: editedRange, replacementString: replacementString ?? "")
        } else {
            rebuildLineCache()
        }
        needsDisplay = true
    }

    func selectionDidChange(selectedRange: NSRange) {
        guard !isHidden else { return }
        ensureLineCache()
        let line = lineIndex(containing: selectedRange.location)
        if currentLineIndex != line {
            currentLineIndex = line
            needsDisplay = true
        }
    }

    func lineInfo(selectedRange: NSRange) -> (current: Int, total: Int) {
        ensureLineCache()
        return (lineIndex(containing: selectedRange.location) + 1, max(1, lineStarts.count))
    }

    func scrollOrFrameDidChange() {
        guard !isHidden else { return }
        needsDisplay = true
    }

    func appearanceDidChange() {
        needsDisplay = true
    }

    private func ensureLineCache() {
        guard let textView else { return }
        let textLength = (textView.string as NSString).length
        if !lineCacheValid || cachedTextLength != textLength {
            rebuildLineCache()
        }
    }

    private func rebuildLineCache() {
        guard let textView else {
            lineStarts = [0]
            cachedTextLength = 0
            lineCacheValid = true
            return
        }
        let text = textView.string as NSString
        var starts = [0]
        starts.reserveCapacity(max(1, text.length / 80))
        if text.length > 0 {
            for i in 0..<text.length where text.character(at: i) == 0x0A {
                starts.append(i + 1)
            }
        }
        lineStarts = starts
        cachedTextLength = text.length
        lineCacheValid = true
        currentLineIndex = min(currentLineIndex, max(0, starts.count - 1))
    }

    private func updateLineCache(editedRange: NSRange, replacementString: String) {
        guard let textView else {
            lineCacheValid = false
            return
        }
        if !lineCacheValid {
            rebuildLineCache()
            return
        }

        let replacementLength = (replacementString as NSString).length
        let newLength = (textView.string as NSString).length
        let oldLength = newLength - replacementLength + editedRange.length
        guard oldLength == cachedTextLength else {
            rebuildLineCache()
            return
        }

        let editStart = max(0, min(editedRange.location, oldLength))
        let editEnd = max(editStart, min(editedRange.location + editedRange.length, oldLength))
        let delta = replacementLength - editedRange.length
        var updated: [Int] = []
        updated.reserveCapacity(lineStarts.count + max(1, replacementLength / 80))

        for start in lineStarts {
            if start <= editStart {
                updated.append(start)
            } else if start > editEnd {
                updated.append(start + delta)
            }
        }

        let replacement = replacementString as NSString
        if replacement.length > 0 {
            for i in 0..<replacement.length where replacement.character(at: i) == 0x0A {
                updated.append(editStart + i + 1)
            }
        }

        updated.sort()
        var deduped: [Int] = []
        deduped.reserveCapacity(updated.count)
        for start in updated where start >= 0 && start <= newLength {
            if deduped.last != start {
                deduped.append(start)
            }
        }
        if deduped.first != 0 {
            deduped.insert(0, at: 0)
        }

        lineStarts = deduped
        cachedTextLength = newLength
        lineCacheValid = true
        currentLineIndex = min(currentLineIndex, max(0, deduped.count - 1))
    }

    private func lineIndex(containing utf16Offset: Int) -> Int {
        let location = max(0, min(utf16Offset, cachedTextLength))
        var low = 0
        var high = lineStarts.count
        while low < high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= location {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return max(0, low - 1)
    }
}
