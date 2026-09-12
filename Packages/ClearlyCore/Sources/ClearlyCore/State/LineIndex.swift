import Foundation

/// UTF-16 offset ⇄ 1-based line number, precomputed once per text revision.
///
/// The editor knows character offsets; `data-sourcepos` in the preview speaks
/// line numbers. Scrolling asks for that conversion on every frame, so walking
/// the string each time is not an option — build this once and binary-search it.
public struct LineIndex {
    /// UTF-16 offset where each line begins. Always starts with `0`, so a
    /// non-empty index has one entry per line.
    private let starts: [Int]
    /// Total UTF-16 length of the indexed text.
    public let length: Int

    public init(_ text: String) {
        var starts: [Int] = [0]
        var offset = 0
        for unit in text.utf16 {
            offset += 1
            if unit == 0x0A { starts.append(offset) }
        }
        // A trailing newline opens a final empty line; that line is real (the
        // caret can sit on it) so the extra start stays.
        self.starts = starts
        self.length = offset
    }

    public var lineCount: Int { starts.count }

    /// 1-based line containing `offset`. Out-of-range offsets clamp to the
    /// first/last line rather than trapping — callers feed this layout-manager
    /// results that can lag a text change by a frame.
    public func line(forCharacterAt offset: Int) -> Int {
        guard offset > 0 else { return 1 }
        guard offset < length else { return starts.count }

        var low = 0
        var high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low + 1
    }

    /// UTF-16 offset where `line` (1-based) begins, clamped to the document.
    public func characterOffset(forLine line: Int) -> Int {
        let index = min(max(line, 1), starts.count) - 1
        return starts[index]
    }
}
