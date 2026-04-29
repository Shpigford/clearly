import Foundation
import ClearlyCore
import MCP
import NaturalLanguage
import XCTest

/// End-to-end coverage of the `find_related` MCP tool.
///
/// Instead of relying on the live `NLContextualEmbedding` model (which
/// requires English assets that aren't always available on test
/// runners), these tests seed deterministic unit vectors directly via
/// `VaultIndex.upsertChunkEmbeddings` so cosine ranking is exact and
/// self-validating.
final class FindRelatedTests: XCTestCase {
    var harness: TestVaultHarness!

    override func setUp() async throws {
        harness = try await TestVaultHarness()
    }

    override func tearDown() async throws {
        await harness?.tearDown()
        harness = nil
    }

    // MARK: - Helpers (mirrored from MCPIntegrationTests)

    private func skipIfEmbeddingAssetsMissing() throws {
        guard let probe = NLContextualEmbedding(language: .english), probe.hasAvailableAssets else {
            throw XCTSkip("NLContextualEmbedding English assets not available on this runner")
        }
    }

    private func unitVector(at index: Int, dim: Int) -> [Float] {
        var v = [Float](repeating: 0, count: dim)
        if dim > 0 { v[index % dim] = 1.0 }
        return v
    }

    private func seedChunk(
        _ index: VaultIndex,
        file: IndexedFile,
        vector: [Float],
        modelVersion: Int = EmbeddingService.MODEL_VERSION
    ) throws {
        let body = "fixture seed for \(file.path)"
        try index.upsertChunkEmbeddings(
            fileID: file.id,
            contentHash: file.contentHash,
            chunks: [
                VaultIndex.ChunkEmbeddingInput(
                    chunkIndex: 0,
                    textOffset: 0,
                    textLength: body.utf8.count,
                    headingPath: [],
                    body: body,
                    vector: vector
                )
            ],
            modelVersion: modelVersion
        )
    }

    // MARK: - Result decoding

    private struct Hit: Decodable {
        let relativePath: String
        let score: Float
    }
    private struct Result: Decodable {
        let vault: String
        let source: String
        let totalCount: Int
        let returnedCount: Int
        let results: [Hit]
    }

    // MARK: - Tests

    func testRanksClosestVectorFirst() async throws {
        try skipIfEmbeddingAssetsMissing()
        let index = harness.loadedVaults[0].index
        let dim = try EmbeddingService().dimension

        // Use real fixture files. The source's mean vector lives at
        // index 0; the "near" file shares index 0; "far" sits at index 2.
        guard
            let source = index.file(forRelativePath: "Notes/Linker.md"),
            let near = index.file(forRelativePath: "README.md"),
            let far = index.file(forRelativePath: "Notes/Link Target.md")
        else {
            return XCTFail("fixture files missing")
        }

        try seedChunk(index, file: source, vector: unitVector(at: 0, dim: dim))
        try seedChunk(index, file: near, vector: unitVector(at: 0, dim: dim))
        try seedChunk(index, file: far, vector: unitVector(at: 2, dim: dim))

        let result = try await harness.callTool(
            "find_related",
            arguments: ["relative_path": .string("Notes/Linker.md")],
            as: Result.self
        )

        XCTAssertEqual(result.source, "Notes/Linker.md")
        XCTAssertEqual(result.totalCount, 2, "source itself must be excluded")
        XCTAssertEqual(result.returnedCount, 2)
        XCTAssertEqual(result.results.first?.relativePath, "README.md", "closest vector should rank first")
        // Scores monotonically non-increasing.
        for i in 1..<result.results.count {
            XCTAssertGreaterThanOrEqual(result.results[i - 1].score, result.results[i].score)
        }
        // Source must never appear.
        XCTAssertFalse(result.results.contains { $0.relativePath == "Notes/Linker.md" })
    }

    func testRespectsLimit() async throws {
        try skipIfEmbeddingAssetsMissing()
        let index = harness.loadedVaults[0].index
        let dim = try EmbeddingService().dimension

        guard let source = index.file(forRelativePath: "Notes/Linker.md") else {
            return XCTFail("source missing from fixture")
        }
        try seedChunk(index, file: source, vector: unitVector(at: 0, dim: dim))
        for file in index.allFiles() where file.id != source.id {
            try seedChunk(index, file: file, vector: unitVector(at: 0, dim: dim))
        }

        let result = try await harness.callTool(
            "find_related",
            arguments: [
                "relative_path": .string("Notes/Linker.md"),
                "limit": .int(2),
            ],
            as: Result.self
        )
        XCTAssertEqual(result.returnedCount, 2)
        XCTAssertGreaterThan(result.totalCount, 2, "totalCount reports the unclamped scored set")
    }

    func testReturnsEmptyResultsWhenSourceHasNoEmbeddings() async throws {
        // No skip — this path doesn't touch the model.
        let result = try await harness.callTool(
            "find_related",
            arguments: ["relative_path": .string("Notes/Linker.md")],
            as: Result.self
        )
        XCTAssertEqual(result.totalCount, 0)
        XCTAssertEqual(result.returnedCount, 0)
        XCTAssertTrue(result.results.isEmpty)
    }

    func testReturnsEmptyResultsWhenSourceEmbeddingsAreStale() async throws {
        let index = harness.loadedVaults[0].index
        guard let source = index.file(forRelativePath: "Notes/Linker.md") else {
            return XCTFail("source missing from fixture")
        }

        try seedChunk(index, file: source, vector: [1, 0])

        let url = harness.vaultURL.appendingPathComponent("Notes/Linker.md")
        try Data("# changed\n".utf8).write(to: url, options: .atomic)
        _ = try index.updateFile(at: "Notes/Linker.md")

        let result = try await harness.callTool(
            "find_related",
            arguments: ["relative_path": .string("Notes/Linker.md")],
            as: Result.self
        )
        XCTAssertEqual(result.totalCount, 0)
        XCTAssertEqual(result.returnedCount, 0)
        XCTAssertTrue(result.results.isEmpty)
    }

    func testMissingSourceErrors() async throws {
        let payload = try await harness.callToolExpectingError(
            "find_related",
            arguments: ["relative_path": .string("does/not/exist.md")]
        )
        XCTAssertEqual(payload.error, "note_not_found")
    }

    func testInvalidLimitRejected() async throws {
        let payload = try await harness.callToolExpectingError(
            "find_related",
            arguments: [
                "relative_path": .string("Notes/Linker.md"),
                "limit": .int(0),
            ]
        )
        XCTAssertEqual(payload.error, "invalid_argument")
    }
}
