import XCTest
@testable import ClearlyCore

final class StatusBarStateTests: XCTestCase {
    func testSelectionChangesKeepDocumentTotals() {
        let state = StatusBarState()
        let text = "**Hello** world from Clearly"

        state.updateText(text)
        state.updateSelection((text as NSString).range(of: "world from"), in: text)

        XCTAssertEqual(state.counts.totalWords, 4)
        XCTAssertEqual(state.counts.totalChars, "Hello world from Clearly".count)
        XCTAssertEqual(state.counts.selectionWords, 2)
        XCTAssertEqual(state.counts.selectionChars, "world from".count)

        state.resetSelection()
        XCTAssertEqual(state.counts.totalWords, 4)
        XCTAssertFalse(state.counts.hasSelection)
    }

    func testTextChangeAfterTextChangeRefreshesTotals() {
        let state = StatusBarState()

        state.updateText("one two")
        XCTAssertEqual(state.counts.totalWords, 2)

        state.updateText("one two three")
        XCTAssertEqual(state.counts.totalWords, 3)
    }
}
