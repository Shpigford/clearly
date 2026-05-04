import XCTest
@testable import ClearlyCore

final class StatusBarStateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: StatusBarState.userDefaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: StatusBarState.userDefaultsKey)
        super.tearDown()
    }

    func testHiddenUpdatesDoNotPublishCountsUntilShown() {
        UserDefaults.standard.set(false, forKey: StatusBarState.userDefaultsKey)
        let state = StatusBarState()
        let text = "Hello world"

        state.updateText(text)
        state.updateSelection((text as NSString).range(of: "world"), in: text)

        XCTAssertEqual(state.counts, .empty)

        state.toggle()

        XCTAssertEqual(state.counts.totalWords, 2)
        XCTAssertEqual(state.counts.selectionWords, 1)
        XCTAssertTrue(state.counts.hasSelection)
    }

    func testHiddenTextChangeRecomputesWhenShownAgain() {
        UserDefaults.standard.set(true, forKey: StatusBarState.userDefaultsKey)
        let state = StatusBarState()

        state.updateText("one two")
        XCTAssertEqual(state.counts.totalWords, 2)

        state.toggle()
        state.updateText("one two three")
        XCTAssertEqual(state.counts.totalWords, 2)

        state.toggle()
        XCTAssertEqual(state.counts.totalWords, 3)
    }

    func testSelectionChangesKeepDocumentTotals() {
        UserDefaults.standard.set(true, forKey: StatusBarState.userDefaultsKey)
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
}
