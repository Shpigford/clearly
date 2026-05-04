import Foundation

public final class StatusBarState: ObservableObject {
    public static let userDefaultsKey = "statusBarVisible"

    @Published public var isVisible: Bool {
        didSet {
            UserDefaults.standard.set(isVisible, forKey: Self.userDefaultsKey)
            if isVisible {
                recomputeAll()
            }
        }
    }
    @Published public private(set) var counts: MarkdownStats.Counts = .empty

    private var lastText: String = ""
    private var lastSelection: NSRange = NSRange(location: 0, length: 0)
    private var cachedTotals: MarkdownStats.Counts = .empty
    private var hasCachedTotals = false

    public init() {
        self.isVisible = UserDefaults.standard.bool(forKey: Self.userDefaultsKey)
    }

    public func toggle() {
        isVisible.toggle()
    }

    /// Replace the cached document text and recompute. Selection length is
    /// preserved if it still fits inside the new text; otherwise it collapses.
    public func updateText(_ text: String) {
        lastText = text
        hasCachedTotals = false
        let nsLength = (text as NSString).length
        if lastSelection.location + lastSelection.length > nsLength {
            lastSelection = NSRange(location: 0, length: 0)
        }
        guard isVisible else { return }
        recomputeAll()
    }

    /// Replace just the selection range. Caller passes the current text so
    /// the cache stays consistent (selection events fire faster than the
    /// debounced text-binding write).
    public func updateSelection(_ range: NSRange, in text: String) {
        lastText = text
        lastSelection = range
        guard isVisible else {
            hasCachedTotals = false
            return
        }
        if hasCachedTotals {
            recomputeSelectionOnly()
        } else {
            recomputeAll()
        }
    }

    /// Clear selection without changing the cached text — used when the
    /// document switches or the editor is dismissed.
    public func resetSelection() {
        lastSelection = NSRange(location: 0, length: 0)
        guard isVisible else { return }
        if hasCachedTotals {
            recomputeSelectionOnly()
        } else {
            recomputeAll()
        }
    }

    private func recomputeAll() {
        counts = MarkdownStats.compute(text: lastText, selectedRange: lastSelection)
        cachedTotals = MarkdownStats.Counts(
            totalWords: counts.totalWords,
            totalChars: counts.totalChars,
            totalReadingSeconds: counts.totalReadingSeconds,
            selectionWords: 0,
            selectionChars: 0,
            hasSelection: false
        )
        hasCachedTotals = true
    }

    private func recomputeSelectionOnly() {
        let selection = selectionCounts()
        counts = MarkdownStats.Counts(
            totalWords: cachedTotals.totalWords,
            totalChars: cachedTotals.totalChars,
            totalReadingSeconds: cachedTotals.totalReadingSeconds,
            selectionWords: selection.words,
            selectionChars: selection.chars,
            hasSelection: selection.hasSelection
        )
    }

    private func selectionCounts() -> (words: Int, chars: Int, hasSelection: Bool) {
        let nsText = lastText as NSString
        guard lastSelection.length > 0,
              lastSelection.location >= 0,
              lastSelection.location + lastSelection.length <= nsText.length else {
            return (0, 0, false)
        }

        let selectedText = nsText.substring(with: lastSelection)
        let selected = MarkdownStats.compute(text: selectedText, selectedRange: NSRange())
        return (selected.totalWords, selected.totalChars, true)
    }
}
