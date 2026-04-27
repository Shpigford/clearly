import XCTest
@testable import ClearlyCore

final class WikiLogWriterTests: XCTestCase {

    private var vault: URL!

    override func setUpWithError() throws {
        vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("wiki-log-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: vault)
    }

    func testFormatsEntryWithGrepableHeader() {
        let op = WikiOperation(
            kind: .capture,
            title: "Ingest: example.com",
            rationale: "Summarized one source.",
            changes: [
                .create(path: "sources/example-com.md", contents: "# x"),
                .modify(path: "index.md", before: "a", after: "b"),
            ],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let entry = WikiLogWriter.formatEntry(op)
        // grep -E '^## \[' should match this line
        XCTAssertTrue(entry.split(separator: "\n").contains(where: { $0.hasPrefix("## [") }))
        XCTAssertTrue(entry.contains("capture — Ingest: example.com"))
        XCTAssertTrue(entry.contains("Summarized one source."))
        XCTAssertTrue(entry.contains("- create `sources/example-com.md`"))
        XCTAssertTrue(entry.contains("- modify `index.md`"))
    }

    func testAppendsToExistingLog() throws {
        let logURL = vault.appendingPathComponent("log.md")
        try "# Log\n\n## [2020-01-01 00:00] ingest — First\n\n".write(to: logURL, atomically: true, encoding: .utf8)

        let op = WikiOperation(
            kind: .review, title: "Lint pass",
            rationale: "", changes: [.create(path: "a.md", contents: "x")]
        )
        try WikiLogWriter.appendOperation(op, to: vault)
        let content = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(content.contains("ingest — First"))
        XCTAssertTrue(content.contains("review — Lint pass"))
        // Karpathy's canonical sanity check
        let headerLines = content.split(separator: "\n").filter { $0.hasPrefix("## [") }
        XCTAssertEqual(headerLines.count, 2)
    }

    func testCreatesLogIfMissing() throws {
        let op = WikiOperation(
            kind: .chat, title: "q?", rationale: "r",
            changes: [.create(path: "answers/a.md", contents: "x")]
        )
        try WikiLogWriter.appendOperation(op, to: vault)
        let content = try String(contentsOf: vault.appendingPathComponent("log.md"), encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("# Log\n"))
        XCTAssertTrue(content.contains("chat — q?"))
    }
}
