import XCTest
@testable import ClearlyCore

final class PreviewChunkerTests: XCTestCase {
    func testShortDocumentProducesSingleChunk() {
        let md = "# Title\n\npara\n"
        let chunks = PreviewChunker.chunks(from: md, targetCharacters: 1000, hardLimitCharacters: 2000)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first?.startLine, 1)
        XCTAssertEqual(chunks.first?.markdown, md)
    }

    func testSplitsOnHeading() {
        // Pad so the first heading's body exceeds the target, forcing a
        // split at the next heading.
        let body = String(repeating: "lorem ipsum dolor sit amet\n", count: 20)
        let md = "# A\n\n\(body)\n## B\n\nmore\n"
        let chunks = PreviewChunker.chunks(from: md, targetCharacters: 100, hardLimitCharacters: 1_000_000)
        XCTAssertGreaterThanOrEqual(chunks.count, 2)
        // Concatenated chunks reproduce the original.
        XCTAssertEqual(chunks.map(\.markdown).joined(), md)
    }

    func testNeverSplitsInsideFencedCodeBlock() {
        // Fenced block large enough that targetCharacters is exceeded
        // mid-fence. Chunker must defer the split until after the closing
        // fence so neither half has a dangling ```.
        let inside = String(repeating: "let x = 1\n", count: 200)
        let md = "# Heading\n\n```swift\n\(inside)```\n\n## Next\n\nmore\n"
        let chunks = PreviewChunker.chunks(from: md, targetCharacters: 200, hardLimitCharacters: 800)

        for chunk in chunks {
            // Each chunk should have an even number of fence lines (every
            // opening fence has a closing fence).
            let fences = chunk.markdown.components(separatedBy: "\n").filter {
                let t = $0.drop { $0 == " " || $0 == "\t" }
                return t.hasPrefix("```") || t.hasPrefix("~~~")
            }
            XCTAssertEqual(fences.count % 2, 0, "chunk has unbalanced fences:\n\(chunk.markdown)")
        }
        XCTAssertEqual(chunks.map(\.markdown).joined(), md)
    }

    func testStartLineMatchesOriginalLineNumbers() {
        let md = "# A\n\npara\n\n## B\n\nmore\n\n## C\n\ntail\n"
        let chunks = PreviewChunker.chunks(from: md, targetCharacters: 8, hardLimitCharacters: 1_000_000)
        XCTAssertEqual(chunks.first?.startLine, 1)
        // Every subsequent chunk's startLine must match the line count of
        // the prior chunks combined plus 1.
        var lineCursor = 1
        for chunk in chunks {
            XCTAssertEqual(chunk.startLine, lineCursor)
            lineCursor += chunk.markdown.filter { $0 == "\n" }.count
        }
    }

    func testTildeFencesAlsoTreatedAsCodeBlocks() {
        let inside = String(repeating: "x\n", count: 100)
        let md = "para\n~~~\n\(inside)~~~\n\nafter\n"
        let chunks = PreviewChunker.chunks(from: md, targetCharacters: 50, hardLimitCharacters: 500)
        for chunk in chunks {
            let fences = chunk.markdown.components(separatedBy: "\n").filter { $0.hasPrefix("~~~") }
            XCTAssertEqual(fences.count % 2, 0)
        }
    }
}
