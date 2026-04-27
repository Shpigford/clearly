import XCTest
@testable import ClearlyCore

final class WikiOperationTests: XCTestCase {

    // MARK: - FileChange Codable wire format

    func testCreateChangeEncodesAsMCPWireFormat() throws {
        let change = FileChange.create(path: "notes/foo.md", contents: "hello")
        let json = try encode(change)
        XCTAssertEqual(json["type"] as? String, "create")
        XCTAssertEqual(json["path"] as? String, "notes/foo.md")
        XCTAssertEqual(json["contents"] as? String, "hello")
        XCTAssertNil(json["before"])
        XCTAssertNil(json["after"])
    }

    func testModifyChangeEncodesAsMCPWireFormat() throws {
        let change = FileChange.modify(path: "index.md", before: "# Old", after: "# New")
        let json = try encode(change)
        XCTAssertEqual(json["type"] as? String, "modify")
        XCTAssertEqual(json["path"] as? String, "index.md")
        XCTAssertEqual(json["before"] as? String, "# Old")
        XCTAssertEqual(json["after"] as? String, "# New")
        XCTAssertNil(json["contents"])
    }

    func testDeleteChangeEncodesAsMCPWireFormat() throws {
        let change = FileChange.delete(path: "obsolete.md", contents: "gone")
        let json = try encode(change)
        XCTAssertEqual(json["type"] as? String, "delete")
        XCTAssertEqual(json["path"] as? String, "obsolete.md")
        XCTAssertEqual(json["contents"] as? String, "gone")
    }

    func testFileChangeRoundTripsThroughJSON() throws {
        let originals: [FileChange] = [
            .create(path: "a.md", contents: "alpha"),
            .modify(path: "b.md", before: "beta", after: "beta-prime"),
            .delete(path: "c.md", contents: "gamma"),
        ]
        for change in originals {
            let data = try JSONEncoder().encode(change)
            let decoded = try JSONDecoder().decode(FileChange.self, from: data)
            XCTAssertEqual(decoded, change)
        }
    }

    // MARK: - WikiOperation Codable

    func testOperationRoundTrip() throws {
        let op = WikiOperation(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            kind: .capture,
            title: "Ingest: example.com",
            rationale: "Summarized source into a new note and updated index.",
            changes: [
                .create(path: "sources/example-com.md", contents: "# Summary"),
                .modify(path: "index.md", before: "- foo", after: "- foo\n- example-com"),
            ],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(op)
        let decoded = try JSONDecoder().decode(WikiOperation.self, from: data)
        XCTAssertEqual(decoded, op)
    }

    // MARK: - Validation

    func testValidateRejectsEmptyChanges() {
        let op = WikiOperation(kind: .capture, title: "t", rationale: "r", changes: [])
        XCTAssertThrowsError(try op.validate()) { error in
            XCTAssertEqual(error as? WikiOperationError, .noChanges)
        }
    }

    func testValidateRejectsDuplicatePaths() {
        let op = WikiOperation(
            kind: .capture, title: "t", rationale: "r",
            changes: [
                .create(path: "dup.md", contents: "a"),
                .modify(path: "dup.md", before: "a", after: "b"),
            ]
        )
        XCTAssertThrowsError(try op.validate()) { error in
            XCTAssertEqual(error as? WikiOperationError, .duplicatePath("dup.md"))
        }
    }

    func testValidateRejectsAbsolutePath() {
        let op = WikiOperation(
            kind: .capture, title: "t", rationale: "r",
            changes: [.create(path: "/etc/passwd", contents: "x")]
        )
        XCTAssertThrowsError(try op.validate()) { error in
            XCTAssertEqual(error as? WikiOperationError, .pathIsAbsolute("/etc/passwd"))
        }
    }

    func testValidateRejectsEscapingPath() {
        let op = WikiOperation(
            kind: .capture, title: "t", rationale: "r",
            changes: [.create(path: "../outside.md", contents: "x")]
        )
        XCTAssertThrowsError(try op.validate()) { error in
            XCTAssertEqual(error as? WikiOperationError, .pathEscapesVault("../outside.md"))
        }
    }

    func testValidateRejectsEmptyPath() {
        let op = WikiOperation(
            kind: .capture, title: "t", rationale: "r",
            changes: [.create(path: "", contents: "x")]
        )
        XCTAssertThrowsError(try op.validate()) { error in
            XCTAssertEqual(error as? WikiOperationError, .pathIsEmpty)
        }
    }

    func testValidateRejectsNoOpModify() {
        let op = WikiOperation(
            kind: .review, title: "t", rationale: "r",
            changes: [.modify(path: "same.md", before: "hello", after: "hello")]
        )
        XCTAssertThrowsError(try op.validate()) { error in
            XCTAssertEqual(error as? WikiOperationError, .noOpModify("same.md"))
        }
    }

    func testValidateAcceptsValidOperation() throws {
        let op = WikiOperation(
            kind: .capture, title: "t", rationale: "r",
            changes: [
                .create(path: "a.md", contents: "x"),
                .modify(path: "b.md", before: "x", after: "y"),
                .delete(path: "c.md", contents: "z"),
            ]
        )
        XCTAssertNoThrow(try op.validate())
    }

    // MARK: - FileChange → LineDiff integration

    func testModifyChangeProducesLineDiffRows() throws {
        let change = FileChange.modify(
            path: "note.md",
            before: "one\ntwo\nthree",
            after: "one\nTWO\nthree"
        )
        guard case .modify(_, let before, let after) = change else {
            return XCTFail("expected modify")
        }
        let rows = try LineDiff.rows(left: before, right: after)
        let ops = rows.map(\.op)
        XCTAssertTrue(ops.contains(.removed))
        XCTAssertTrue(ops.contains(.added))
        XCTAssertTrue(ops.contains(.same))
    }

    // MARK: - Helpers

    private func encode(_ change: FileChange) throws -> [String: Any] {
        let data = try JSONEncoder().encode(change)
        let any = try JSONSerialization.jsonObject(with: data)
        return any as? [String: Any] ?? [:]
    }
}
