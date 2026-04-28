import XCTest
import Foundation
@testable import ClearlyCore

final class VaultIndexEmbeddingsTests: XCTestCase {

    private var tempVault: URL!

    override func setUpWithError() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("clearly-embeddings-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        tempVault = tmp
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempVault)
    }

    private func writeNote(_ name: String, body: String) throws -> String {
        let url = tempVault.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        return name
    }

    private func freshIndex() throws -> VaultIndex {
        try VaultIndex(locationURL: tempVault)
    }

    private func chunk(
        index: Int = 0,
        body: String = "body",
        headingPath: [String] = [],
        vector: [Float]
    ) -> VaultIndex.ChunkEmbeddingInput {
        VaultIndex.ChunkEmbeddingInput(
            chunkIndex: index,
            textOffset: 0,
            textLength: body.utf8.count,
            headingPath: headingPath,
            body: body,
            vector: vector
        )
    }

    // MARK: - Migration runs cleanly

    func testMigrationCreatesChunkedEmbeddingsTable() throws {
        let index = try freshIndex()
        // Sanity-check by issuing a query that depends on both `embeddings` (v3 shape) and
        // `chunks_fts` existing.
        XCTAssertEqual(try index.embeddingsMissingOrStale(modelVersion: 1), [])
        XCTAssertEqual(index.searchByKeywords(["alpha"]).count, 0)
    }

    // MARK: - Upsert / fetch round-trip

    func testUpsertRoundTripPreservesChunk() throws {
        let index = try freshIndex()
        _ = try writeNote("alpha.md", body: "# Alpha\n\nThis is the alpha note.")
        index.indexAllFiles()

        let alpha = try XCTUnwrap(index.file(forRelativePath: "alpha.md"))
        let vector: [Float] = [0.1, -0.5, 1e-4, 7.25, -0.0001]
        try index.upsertChunkEmbeddings(
            fileID: alpha.id,
            contentHash: alpha.contentHash,
            chunks: [chunk(headingPath: ["Alpha"], vector: vector)],
            modelVersion: 1
        )

        let stored = try index.chunkEmbeddings(forFileID: alpha.id)
        XCTAssertEqual(stored.count, 1)
        let only = try XCTUnwrap(stored.first)
        XCTAssertEqual(only.fileID, alpha.id)
        XCTAssertEqual(only.path, "alpha.md")
        XCTAssertEqual(only.chunkIndex, 0)
        XCTAssertEqual(only.headingPath, ["Alpha"])
        XCTAssertEqual(only.vector, vector)
    }

    func testUpsertReplacesPriorChunksForFile() throws {
        let index = try freshIndex()
        _ = try writeNote("a.md", body: "a")
        index.indexAllFiles()
        let a = try XCTUnwrap(index.file(forRelativePath: "a.md"))

        // First write: 3 chunks.
        try index.upsertChunkEmbeddings(
            fileID: a.id, contentHash: a.contentHash,
            chunks: [
                chunk(index: 0, vector: [1, 2, 3]),
                chunk(index: 1, vector: [4, 5, 6]),
                chunk(index: 2, vector: [7, 8, 9]),
            ],
            modelVersion: 1
        )
        XCTAssertEqual(try index.chunkEmbeddings(forFileID: a.id).count, 3)

        // Re-upsert with a single chunk: prior rows must be wiped, leaving 1.
        try index.upsertChunkEmbeddings(
            fileID: a.id, contentHash: a.contentHash,
            chunks: [chunk(index: 0, vector: [9, 9, 9])],
            modelVersion: 1
        )
        let after = try index.chunkEmbeddings(forFileID: a.id)
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after.first?.vector, [9, 9, 9])
    }

    // MARK: - Cascade delete

    func testDeletingFileCascadesToChunks() throws {
        let index = try freshIndex()
        let path = try writeNote("doomed.md", body: "soon to be removed")
        index.indexAllFiles()
        let doomed = try XCTUnwrap(index.file(forRelativePath: path))
        try index.upsertChunkEmbeddings(
            fileID: doomed.id, contentHash: doomed.contentHash,
            chunks: [chunk(vector: [1, 2])],
            modelVersion: 1
        )
        XCTAssertEqual(try index.chunkEmbeddings(forFileID: doomed.id).count, 1)

        try FileManager.default.removeItem(at: tempVault.appendingPathComponent(path))
        _ = try index.updateFile(at: path)

        XCTAssertEqual(try index.chunkEmbeddings(forFileID: doomed.id), [])
    }

    // MARK: - Stale detection

    func testMissingOrStaleSurfacesNewFiles() throws {
        let index = try freshIndex()
        _ = try writeNote("new.md", body: "fresh content")
        index.indexAllFiles()

        let stale = try index.embeddingsMissingOrStale(modelVersion: 1)
        XCTAssertEqual(stale.map(\.path), ["new.md"])
    }

    func testMissingOrStaleSurfacesContentHashDrift() throws {
        let index = try freshIndex()
        _ = try writeNote("drift.md", body: "v1")
        index.indexAllFiles()
        let v1 = try XCTUnwrap(index.file(forRelativePath: "drift.md"))
        try index.upsertChunkEmbeddings(
            fileID: v1.id, contentHash: v1.contentHash,
            chunks: [chunk(vector: [0.5])],
            modelVersion: 1
        )
        XCTAssertEqual(try index.embeddingsMissingOrStale(modelVersion: 1), [])

        try "v2 — different".write(to: tempVault.appendingPathComponent("drift.md"),
                                    atomically: true, encoding: .utf8)
        _ = try index.updateFile(at: "drift.md")

        let stale = try index.embeddingsMissingOrStale(modelVersion: 1)
        XCTAssertEqual(stale.map(\.path), ["drift.md"])
    }

    func testMissingOrStaleSurfacesModelVersionBump() throws {
        let index = try freshIndex()
        _ = try writeNote("ver.md", body: "anything")
        index.indexAllFiles()
        let row = try XCTUnwrap(index.file(forRelativePath: "ver.md"))
        try index.upsertChunkEmbeddings(
            fileID: row.id, contentHash: row.contentHash,
            chunks: [chunk(vector: [1])],
            modelVersion: 1
        )

        XCTAssertEqual(try index.embeddingsMissingOrStale(modelVersion: 1), [])
        let staleAt2 = try index.embeddingsMissingOrStale(modelVersion: 2)
        XCTAssertEqual(staleAt2.map(\.path), ["ver.md"])
    }

    // MARK: - allChunkEmbeddings filters by model version + content hash

    func testAllChunkEmbeddingsFiltersByModelVersion() throws {
        let index = try freshIndex()
        _ = try writeNote("a.md", body: "a")
        _ = try writeNote("b.md", body: "b")
        index.indexAllFiles()
        let a = try XCTUnwrap(index.file(forRelativePath: "a.md"))
        let b = try XCTUnwrap(index.file(forRelativePath: "b.md"))
        try index.upsertChunkEmbeddings(fileID: a.id, contentHash: a.contentHash,
                                        chunks: [chunk(vector: [1, 0])], modelVersion: 1)
        try index.upsertChunkEmbeddings(fileID: b.id, contentHash: b.contentHash,
                                        chunks: [chunk(vector: [0, 1])], modelVersion: 2)

        XCTAssertEqual(try index.allChunkEmbeddings(modelVersion: 1).map(\.path), ["a.md"])
        XCTAssertEqual(try index.allChunkEmbeddings(modelVersion: 2).map(\.path), ["b.md"])
    }

    func testAllChunkEmbeddingsSkipsStaleContentHash() throws {
        let index = try freshIndex()
        _ = try writeNote("drift.md", body: "v1")
        index.indexAllFiles()
        let v1 = try XCTUnwrap(index.file(forRelativePath: "drift.md"))
        try index.upsertChunkEmbeddings(fileID: v1.id, contentHash: v1.contentHash,
                                        chunks: [chunk(vector: [1, 0])], modelVersion: 1)

        try "v2 - different".write(to: tempVault.appendingPathComponent("drift.md"),
                                    atomically: true, encoding: .utf8)
        _ = try index.updateFile(at: "drift.md")

        XCTAssertEqual(try index.allChunkEmbeddings(modelVersion: 1), [])
    }

    func testAllChunkEmbeddingsReturnsMultipleChunksPerFile() throws {
        let index = try freshIndex()
        _ = try writeNote("multi.md", body: "multi-section note")
        index.indexAllFiles()
        let m = try XCTUnwrap(index.file(forRelativePath: "multi.md"))
        try index.upsertChunkEmbeddings(
            fileID: m.id, contentHash: m.contentHash,
            chunks: [
                chunk(index: 0, vector: [1, 0]),
                chunk(index: 1, vector: [0, 1]),
                chunk(index: 2, vector: [1, 1]),
            ],
            modelVersion: 1
        )

        let all = try index.allChunkEmbeddings(modelVersion: 1)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(Set(all.map(\.chunkIndex)), [0, 1, 2])
        XCTAssertEqual(Set(all.map(\.path)), ["multi.md"])
    }

    // MARK: - chunks_fts: keyword search routes through chunk text

    func testSearchByKeywordsHitsChunkBodies() throws {
        let index = try freshIndex()
        _ = try writeNote("local.md", body: "Local-First Software notes")
        _ = try writeNote("other.md", body: "Unrelated topic")
        index.indexAllFiles()
        let local = try XCTUnwrap(index.file(forRelativePath: "local.md"))
        let other = try XCTUnwrap(index.file(forRelativePath: "other.md"))

        try index.upsertChunkEmbeddings(
            fileID: local.id, contentHash: local.contentHash,
            chunks: [chunk(body: "all about local-first software architecture", vector: [1])],
            modelVersion: EmbeddingService.MODEL_VERSION
        )
        try index.upsertChunkEmbeddings(
            fileID: other.id, contentHash: other.contentHash,
            chunks: [chunk(body: "rambling unrelated content", vector: [1])],
            modelVersion: EmbeddingService.MODEL_VERSION
        )

        let results = index.searchByKeywords(["local-first"])
        XCTAssertEqual(results.map(\.path), ["local.md"])
    }

    func testSearchByKeywordsRanksByBM25() throws {
        let index = try freshIndex()
        _ = try writeNote("strong.md", body: "x")
        _ = try writeNote("weak.md", body: "x")
        index.indexAllFiles()
        let strong = try XCTUnwrap(index.file(forRelativePath: "strong.md"))
        let weak = try XCTUnwrap(index.file(forRelativePath: "weak.md"))

        try index.upsertChunkEmbeddings(
            fileID: strong.id, contentHash: strong.contentHash,
            chunks: [chunk(body: "kafka kafka kafka kafka kafka producer streams", vector: [1])],
            modelVersion: EmbeddingService.MODEL_VERSION
        )
        try index.upsertChunkEmbeddings(
            fileID: weak.id, contentHash: weak.contentHash,
            chunks: [chunk(body: "the word kafka appears once here", vector: [1])],
            modelVersion: EmbeddingService.MODEL_VERSION
        )

        let results = index.searchByKeywords(["kafka"])
        XCTAssertEqual(results.first?.path, "strong.md")
    }

    func testSearchByKeywordsSkipsStaleChunksAfterContentHashDrift() throws {
        let index = try freshIndex()
        _ = try writeNote("drift.md", body: "old keyword")
        index.indexAllFiles()
        let v1 = try XCTUnwrap(index.file(forRelativePath: "drift.md"))
        try index.upsertChunkEmbeddings(
            fileID: v1.id, contentHash: v1.contentHash,
            chunks: [chunk(body: "old keyword", vector: [1])],
            modelVersion: EmbeddingService.MODEL_VERSION
        )
        XCTAssertEqual(index.searchByKeywords(["keyword"]).map(\.path), ["drift.md"])

        try "replacement text".write(to: tempVault.appendingPathComponent("drift.md"),
                                      atomically: true, encoding: .utf8)
        _ = try index.updateFile(at: "drift.md")

        XCTAssertEqual(index.searchByKeywords(["keyword"]), [])
    }

    // MARK: - deleteAllEmbeddings

    func testDeleteAllEmbeddingsClearsBothTables() throws {
        let index = try freshIndex()
        _ = try writeNote("x.md", body: "x")
        index.indexAllFiles()
        let x = try XCTUnwrap(index.file(forRelativePath: "x.md"))
        try index.upsertChunkEmbeddings(
            fileID: x.id, contentHash: x.contentHash,
            chunks: [chunk(body: "indexed body", vector: [1, 2])],
            modelVersion: 1
        )

        try index.deleteAllEmbeddings()

        XCTAssertEqual(try index.chunkEmbeddings(forFileID: x.id), [])
        XCTAssertEqual(try index.embeddingsMissingOrStale(modelVersion: 1).map(\.path), ["x.md"])
        XCTAssertEqual(index.searchByKeywords(["indexed"]).count, 0)
    }
}
