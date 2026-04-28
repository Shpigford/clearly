import XCTest
@testable import ClearlyCore

final class WikiSystemFilesTests: XCTestCase {

    func testReservedRootFilesAreExcluded() {
        XCTAssertTrue(WikiSystemFiles.isExcluded(vaultRelativePath: "index.md"))
        XCTAssertTrue(WikiSystemFiles.isExcluded(vaultRelativePath: "log.md"))
        XCTAssertTrue(WikiSystemFiles.isExcluded(vaultRelativePath: "AGENTS.md"))
        XCTAssertTrue(WikiSystemFiles.isExcluded(vaultRelativePath: "getting-started.md"))
    }

    func testReservedFolderContentsAreExcluded() {
        XCTAssertTrue(WikiSystemFiles.isExcluded(vaultRelativePath: "raw/article.md"))
        XCTAssertTrue(WikiSystemFiles.isExcluded(vaultRelativePath: "raw/sub/deeper.md"))
        XCTAssertTrue(WikiSystemFiles.isExcluded(vaultRelativePath: "_audit/2026-04.md"))
    }

    func testHiddenSegmentsAreExcluded() {
        XCTAssertTrue(WikiSystemFiles.isExcluded(vaultRelativePath: ".clearly/state.json"))
        XCTAssertTrue(WikiSystemFiles.isExcluded(vaultRelativePath: ".hidden.md"))
        XCTAssertTrue(WikiSystemFiles.isExcluded(vaultRelativePath: "concepts/.draft.md"))
    }

    func testReservedFilenamesAreOnlyExcludedAtRoot() {
        // A note someone calls `index.md` in a subfolder is user content,
        // not the wiki's table of contents.
        XCTAssertFalse(WikiSystemFiles.isExcluded(vaultRelativePath: "Notes/index.md"))
        XCTAssertFalse(WikiSystemFiles.isExcluded(vaultRelativePath: "people/log.md"))
    }

    func testReservedFolderNamesAreSegmentAnchored() {
        // Substring matches must NOT trip the predicate — `raw_data.md` at root
        // is user content.
        XCTAssertFalse(WikiSystemFiles.isExcluded(vaultRelativePath: "raw_data.md"))
        XCTAssertFalse(WikiSystemFiles.isExcluded(vaultRelativePath: "audit-notes.md"))
    }

    func testRegularNotesAreNotExcluded() {
        XCTAssertFalse(WikiSystemFiles.isExcluded(vaultRelativePath: "concepts/foo.md"))
        XCTAssertFalse(WikiSystemFiles.isExcluded(vaultRelativePath: "people/jane.md"))
        XCTAssertFalse(WikiSystemFiles.isExcluded(vaultRelativePath: "thoughts.md"))
    }

    func testEmptyPathIsExcluded() {
        XCTAssertTrue(WikiSystemFiles.isExcluded(vaultRelativePath: ""))
    }
}
