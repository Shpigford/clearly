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
        let op = try AgentResultParser.parseWikiOperation(from: text, kind: .ingest)
        XCTAssertEqual(op.kind, .ingest)
        XCTAssertEqual(op.title, "Ingest: alpha")
        XCTAssertEqual(op.changes.count, 1)
    }

    func testRejectsEmptyChanges() {
        let text = #"{"title":"t","rationale":"r","changes":[]}"#
        XCTAssertThrowsError(try AgentResultParser.parseWikiOperation(from: text, kind: .ingest))
    }

    func testRejectsResponseWithNoJSON() {
        XCTAssertThrowsError(try AgentResultParser.parseWikiOperation(from: "No JSON here.", kind: .ingest))
    }

    // MARK: - Anthropic response decoding

    func testDecodesAnthropicEnvelope() throws {
        let raw = """
        {
          "content": [
            {"type": "text", "text": "hello"},
            {"type": "text", "text": " world"}
          ],
          "usage": {"input_tokens": 12, "output_tokens": 5}
        }
        """
        let data = raw.data(using: .utf8)!
        let result = try AnthropicAPIAgentRunner.decode(data: data, model: "claude-sonnet-4-6")
        XCTAssertEqual(result.text, "hello world")
        XCTAssertEqual(result.inputTokens, 12)
        XCTAssertEqual(result.outputTokens, 5)
        XCTAssertEqual(result.model, "claude-sonnet-4-6")
    }

    func testDecodeRejectsEmptyText() {
        let raw = """
        { "content": [], "usage": {"input_tokens": 1, "output_tokens": 1} }
        """
        let data = raw.data(using: .utf8)!
        XCTAssertThrowsError(try AnthropicAPIAgentRunner.decode(data: data, model: "m"))
    }
}
