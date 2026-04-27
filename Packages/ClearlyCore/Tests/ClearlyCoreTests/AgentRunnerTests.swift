import XCTest
@testable import ClearlyCore

final class AgentRunnerTests: XCTestCase {

    // MARK: - JSON extraction

    func testExtractsPureJSON() {
        let text = #"{"title":"x","rationale":"y","changes":[]}"#
        XCTAssertEqual(AgentResultParser.extractFirstJSONObject(in: text), text)
    }

    func testExtractsJSONFromProseWrapper() {
        let text = """
        Sure, here's the operation:
        {"title":"x","rationale":"y","changes":[{"type":"create","path":"a.md","contents":"hello"}]}
        Let me know if you want me to adjust.
        """
        let extracted = AgentResultParser.extractFirstJSONObject(in: text)
        XCTAssertTrue(extracted?.hasPrefix("{") == true)
        XCTAssertTrue(extracted?.hasSuffix("}") == true)
    }

    func testExtractsJSONWithNestedBracesInStrings() {
        let text = #"{"title":"x {y} z","changes":[]}"#
        XCTAssertEqual(AgentResultParser.extractFirstJSONObject(in: text), text)
    }

    func testReturnsNilWhenNoJSON() {
        XCTAssertNil(AgentResultParser.extractFirstJSONObject(in: "plain text, no object"))
    }

    // MARK: - WikiOperation parsing

    func testParsesValidWikiOperation() throws {
        let text = """
        {
          "title": "Ingest: alpha",
          "rationale": "summarised one source",
          "changes": [
            {"type": "create", "path": "sources/alpha.md", "contents": "# Alpha"}
          ]
        }
        """
        let op = try AgentResultParser.parseWikiOperation(from: text, kind: .capture)
        XCTAssertEqual(op.kind, .capture)
        XCTAssertEqual(op.title, "Ingest: alpha")
        XCTAssertEqual(op.changes.count, 1)
    }

    func testRejectsEmptyChanges() {
        let text = #"{"title":"t","rationale":"r","changes":[]}"#
        XCTAssertThrowsError(try AgentResultParser.parseWikiOperation(from: text, kind: .capture))
    }

    func testRejectsResponseWithNoJSON() {
        XCTAssertThrowsError(try AgentResultParser.parseWikiOperation(from: "No JSON here.", kind: .capture))
    }
}
