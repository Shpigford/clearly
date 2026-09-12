import Foundation

public struct PreviewSourceAnchor: Hashable {
    public let startLine: Int
    public let startColumn: Int
    public let endLine: Int
    public let endColumn: Int
    public let progress: Double

    public var approximateLine: Double {
        let span = max(0, endLine - startLine)
        return Double(startLine) + (Double(span) * progress)
    }
}

/// Where the reader is in the *document*, not in the view.
///
/// Editor and preview have unrelated pixel heights — a fenced code block is
/// twenty source lines and renders compact, a heading is one line and renders
/// tall — so a shared scroll percentage lands on different content in each
/// mode. `line` is the ground truth: a 1-based source line, fractional so the
/// remainder carries progress *between* two lines. `fraction` stays as the
/// fallback for the moments before either side has resolved a line.
public struct ScrollAnchor: Hashable {
    /// 1-based source line at the top of the viewport, fractional.
    /// `0` means "not resolved" — use `fraction` instead.
    public let line: Double
    /// Normalized scroll offset (0...1) of the view that captured this anchor.
    public let fraction: Double

    public init(line: Double, fraction: Double) {
        self.line = line
        self.fraction = fraction
    }

    public var hasLine: Bool { line > 0 }
}

/// Dead-simple scroll position bridge between editor and preview, keyed per window.
public enum ScrollBridge {
    private static var anchors: [String: ScrollAnchor] = [:]

    public static func anchor(for id: String) -> ScrollAnchor {
        anchors[id] ?? ScrollAnchor(line: 0, fraction: 0)
    }

    public static func setAnchor(_ value: ScrollAnchor, for id: String) {
        anchors[id] = value
    }

}

/// Stores current text selection per window so the destination view can highlight it on mode switch.
public enum SelectionBridge {
    private static var selections: [String: String] = [:]

    public static func selection(for id: String) -> String? {
        selections[id]
    }

    public static func setSelection(_ text: String?, for id: String) {
        if let text, !text.isEmpty {
            selections[id] = text
        } else {
            selections[id] = nil
        }
    }
}
