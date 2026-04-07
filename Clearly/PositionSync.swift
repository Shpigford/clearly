import Foundation

struct PreviewSourceAnchor: Hashable {
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

/// Dead-simple scroll position bridge between editor and preview, keyed per window.
enum ScrollBridge {
    private static var fractions: [String: Double] = [:]

    static func fraction(for id: String) -> Double {
        fractions[id] ?? 0
    }

    static func setFraction(_ value: Double, for id: String) {
        fractions[id] = value
    }
}
