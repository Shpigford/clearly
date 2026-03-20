import Foundation
import WebKit

struct PreviewSourceAnchor {
    let startLine: Int
    let startColumn: Int
    let endLine: Int
    let endColumn: Int
    let progress: Double

    var approximateLine: Double {
        let span = max(0, endLine - startLine)
        return Double(startLine) + (Double(span) * progress)
    }
}

class ScrollSync: ObservableObject {
    enum ScrollSource { case none, editor, preview }

    var scrollSource: ScrollSource = .none
    var topLine: Double = 1
    weak var previewWebView: WKWebView?
    weak var editorScrollView: NSScrollView?
    private var lastPreviewAnchor: PreviewSourceAnchor?

    private func resetSource(_ expected: ScrollSource) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            if self?.scrollSource == expected { self?.scrollSource = .none }
        }
    }

    func editorDidScroll(line: Double) {
        guard scrollSource != .preview else { return }
        scrollSource = .editor
        topLine = line
        lastPreviewAnchor = nil
        syncPreviewToLine(line)
        resetSource(.editor)
    }

    func previewDidScroll(anchor: PreviewSourceAnchor) {
        guard scrollSource != .editor else { return }
        scrollSource = .preview
        topLine = anchor.approximateLine
        lastPreviewAnchor = anchor
        syncEditorToAnchor(anchor)
        resetSource(.preview)
    }

    func syncPreviewToLine(_ line: Double) {
        // Compute target Y from cached positions and hand off to the RAF lerp loop.
        // The loop smoothly interpolates at the browser's frame rate, so uneven
        // evaluateJavaScript arrival times don't cause jitter.
        let js = """
        (function() {
            var c = window._spCache;
            if (!c || !c.length) return;
            var current = c[0], next = null;
            for (var i = 0; i < c.length; i++) {
                if (c[i].startLine <= \(line)) {
                    current = c[i];
                } else {
                    next = c[i];
                    break;
                }
            }
            var y;
            if (\(line) >= current.startLine && \(line) <= current.endLine && current.endLine > current.startLine) {
                var blockFrac = (\(line) - current.startLine) / (current.endLine - current.startLine);
                y = current.top + blockFrac * (current.bottom - current.top);
            } else if (next) {
                var currentEnd = Math.max(current.startLine, current.endLine);
                if (next.startLine > currentEnd && \(line) > currentEnd) {
                    var gapFrac = (\(line) - currentEnd) / (next.startLine - currentEnd);
                    y = current.bottom + Math.max(0, Math.min(1, gapFrac)) * (next.top - current.bottom);
                } else {
                    y = current.top;
                }
            } else {
                y = current.bottom;
            }
            window._targetScrollY = Math.max(0, y - window.innerHeight / 2);
            window._syncFromEditor = true;
        })();
        """
        previewWebView?.evaluateJavaScript(js)
    }

    func syncPreviewToAnchor(_ anchor: PreviewSourceAnchor) {
        let js = """
        (function() {
            var c = window._spCache;
            if (!c || !c.length) return;
            var match = null;
            for (var i = 0; i < c.length; i++) {
                if (
                    c[i].startLine === \(anchor.startLine) &&
                    c[i].startColumn === \(anchor.startColumn) &&
                    c[i].endLine === \(anchor.endLine) &&
                    c[i].endColumn === \(anchor.endColumn)
                ) {
                    match = c[i];
                    break;
                }
            }
            var y;
            if (match) {
                y = match.top + Math.max(0, Math.min(1, \(anchor.progress))) * (match.bottom - match.top);
            } else {
                var line = \(anchor.approximateLine);
                var current = c[0], next = null;
                for (var i = 0; i < c.length; i++) {
                    if (c[i].startLine <= line) {
                        current = c[i];
                    } else {
                        next = c[i];
                        break;
                    }
                }
                if (line >= current.startLine && line <= current.endLine && current.endLine > current.startLine) {
                    var blockFrac = (line - current.startLine) / (current.endLine - current.startLine);
                    y = current.top + blockFrac * (current.bottom - current.top);
                } else if (next) {
                    var currentEnd = Math.max(current.startLine, current.endLine);
                    if (next.startLine > currentEnd && line > currentEnd) {
                        var gapFrac = (line - currentEnd) / (next.startLine - currentEnd);
                        y = current.bottom + Math.max(0, Math.min(1, gapFrac)) * (next.top - current.bottom);
                    } else {
                        y = current.top;
                    }
                } else {
                    y = current.bottom;
                }
            }
            window._targetScrollY = Math.max(0, y - window.innerHeight / 2);
            window._syncFromEditor = true;
        })();
        """
        previewWebView?.evaluateJavaScript(js)
    }

    func syncPreview() {
        if let lastPreviewAnchor {
            syncPreviewToAnchor(lastPreviewAnchor)
        } else {
            syncPreviewToLine(topLine)
        }
    }

    func syncEditorToAnchor(_ anchor: PreviewSourceAnchor) {
        guard let scrollView = editorScrollView,
              let textView = scrollView.documentView as? NSTextView,
              let layoutManager = textView.layoutManager else { return }

        let text = textView.string as NSString
        guard text.length > 0 else {
            scrollView.contentView.setBoundsOrigin(.zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return
        }

        let startOffset = utf16Offset(in: text, line: anchor.startLine, column: anchor.startColumn)
        let endOffset = utf16Offset(in: text, line: anchor.endLine, column: anchor.endColumn)
        let lower = min(startOffset, endOffset)
        let upper = max(startOffset, endOffset)
        let targetOffset = lower + Int(round(Double(upper - lower) * max(0, min(1, anchor.progress))))
        let safeOffset = min(max(0, targetOffset), max(0, text.length - 1))

        let glyphIndex = layoutManager.glyphIndexForCharacter(at: safeOffset)
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)

        let halfViewport = scrollView.contentView.bounds.height / 2
        let y = max(0, lineRect.origin.y - halfViewport)
        scrollView.contentView.setBoundsOrigin(NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func utf16Offset(in text: NSString, line: Int, column: Int) -> Int {
        let targetLine = max(1, line)
        var currentLine = 1
        var lineStart = 0

        while currentLine < targetLine && lineStart < text.length {
            let nextLineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
            lineStart = NSMaxRange(nextLineRange)
            currentLine += 1
        }

        if lineStart >= text.length {
            return text.length
        }

        let lineRange = text.lineRange(for: NSRange(location: lineStart, length: 0))
        var lineEnd = NSMaxRange(lineRange)
        while lineEnd > lineRange.location {
            let scalar = text.character(at: lineEnd - 1)
            if scalar == 10 || scalar == 13 {
                lineEnd -= 1
            } else {
                break
            }
        }

        let clampedColumn = max(1, column)
        let offsetInLine = min(clampedColumn - 1, max(0, lineEnd - lineStart))
        return min(text.length, lineStart + offsetInLine)
    }
}
