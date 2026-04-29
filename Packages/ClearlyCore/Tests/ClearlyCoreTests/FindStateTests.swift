import XCTest
@testable import ClearlyCore

final class FindStateTests: XCTestCase {
    func testCanNavigateWhenResultsAreStale() {
        let state = FindState()
        state.query = "needle"
        state.matchCount = 0
        state.resultsAreStale = true

        XCTAssertTrue(state.canNavigate)
    }

    func testCannotNavigateEmptyOrKnownNoResults() {
        let state = FindState()
        XCTAssertFalse(state.canNavigate)

        state.query = "needle"
        state.matchCount = 0
        state.resultsAreStale = false
        XCTAssertFalse(state.canNavigate)
    }
}
