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

/// Dead-simple scroll position bridge between editor and preview, keyed per window.
public enum ScrollBridge {
    private static var fractions: [String: Double] = [:]

    public static func fraction(for id: String) -> Double {
        fractions[id] ?? 0
    }

    public static func setFraction(_ value: Double, for id: String) {
        fractions[id] = value
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
