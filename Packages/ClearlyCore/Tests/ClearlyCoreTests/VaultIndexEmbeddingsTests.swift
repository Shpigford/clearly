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

    // MARK: - Migration runs cleanly

    func testMigrationCreatesEmbeddingsTable() throws {
        let index = try freshIndex()
        // No assertion needed beyond init succeeding — the migrator throws if v2 fails.
        // Sanity-check by issuing a query that depends on the table existing:
        let stale = try index.embeddingsMissingOrStale(modelVersion: 1)
        XCTAssertEqual(stale, [])
    }

    // MARK: - Upsert / fetch round-trip

    func testUpsertRoundTripPreservesVector() throws {
        let index = try freshIndex()
        _ = try writeNote("alpha.md", body: "# Alpha\n\nThis is the alpha note.")
        index.indexAllFiles()

        let alpha = try XCTUnwrap(index.file(forRelativePath: "alpha.md"))
        let vector: [Float] = [0.1, -0.5, 1e-4, 7.25, -0.0001]
        try index.upsertEmbedding(fileID: alpha.id, contentHash: alpha.contentHash,
                                  vector: vector, modelVersion: 1)

        let stored = try XCTUnwrap(index.embedding(forFileID: alpha.id))
        XCTAssertEqual(stored.fileID, alpha.id)
        XCTAssertEqual(stored.path, "alpha.md")
        XCTAssertEqual(stored.vector, vector)
    }

    func testUpsertOverwritesPriorVector() throws {
        let index = try freshIndex()
        _ = try writeNote("a.md", body: "a")
        index.indexAllFiles()
        let a = try XCTUnwrap(index.file(forRelativePath: "a.md"))

        try index.upsertEmbedding(fileID: a.id, contentHash: a.contentHash, vector: [1, 2, 3], modelVersion: 1)
        try index.upsertEmbedding(fileID: a.id, contentHash: a.contentHash, vector: [9, 9, 9], modelVersion: 1)

        let stored = try XCTUnwrap(index.embedding(forFileID: a.id))
        XCTAssertEqual(stored.vector, [9, 9, 9])
    }

    // MARK: - Cascade delete

    func testDeletingFileCascadesToEmbedding() throws {
        let index = try freshIndex()
        let path = try writeNote("doomed.md", body: "soon to be removed")
        index.indexAllFiles()
        let doomed = try XCTUnwrap(index.file(forRelativePath: path))
        try index.upsertEmbedding(fileID: doomed.id, contentHash: doomed.contentHash,
                                  vector: [1, 2], modelVersion: 1)
        XCTAssertNotNil(try index.embedding(forFileID: doomed.id))

        // Remove the file; updateFile(at:) deletes the row, which should cascade.
        try FileManager.default.removeItem(at: tempVault.appendingPathComponent(path))
        _ = try index.updateFile(at: path)

        XCTAssertNil(try index.embedding(forFileID: doomed.id))
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
        try index.upsertEmbedding(fileID: v1.id, contentHash: v1.contentHash,
                                  vector: [0.5], modelVersion: 1)
        XCTAssertEqual(try index.embeddingsMissingOrStale(modelVersion: 1), [])

        // Mutate content; reindex; now the embedding's stored content_hash is stale.
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
        try index.upsertEmbedding(fileID: row.id, contentHash: row.contentHash,
                                  vector: [1], modelVersion: 1)

        // At v1 → fresh; at v2 → stale.
        XCTAssertEqual(try index.embeddingsMissingOrStale(modelVersion: 1), [])
        let staleAt2 = try index.embeddingsMissingOrStale(modelVersion: 2)
        XCTAssertEqual(staleAt2.map(\.path), ["ver.md"])
    }

    // MARK: - allEmbeddings filters by model version

    func testAllEmbeddingsFiltersByModelVersion() throws {
        let index = try freshIndex()
        _ = try writeNote("a.md", body: "a")
        _ = try writeNote("b.md", body: "b")
        index.indexAllFiles()
        let a = try XCTUnwrap(index.file(forRelativePath: "a.md"))
        let b = try XCTUnwrap(index.file(forRelativePath: "b.md"))
        try index.upsertEmbedding(fileID: a.id, contentHash: a.contentHash,
                                  vector: [1, 0], modelVersion: 1)
        try index.upsertEmbedding(fileID: b.id, contentHash: b.contentHash,
                                  vector: [0, 1], modelVersion: 2)

        XCTAssertEqual(try index.allEmbeddings(modelVersion: 1).map(\.path), ["a.md"])
        XCTAssertEqual(try index.allEmbeddings(modelVersion: 2).map(\.path), ["b.md"])
    }

    func testAllEmbeddingsSkipsStaleContentHash() throws {
        let index = try freshIndex()
        _ = try writeNote("drift.md", body: "v1")
        index.indexAllFiles()
        let v1 = try XCTUnwrap(index.file(forRelativePath: "drift.md"))
        try index.upsertEmbedding(fileID: v1.id, contentHash: v1.contentHash,
                                  vector: [1, 0], modelVersion: 1)

        try "v2 - different".write(to: tempVault.appendingPathComponent("drift.md"),
                                    atomically: true, encoding: .utf8)
        _ = try index.updateFile(at: "drift.md")

        XCTAssertEqual(try index.allEmbeddings(modelVersion: 1), [])
    }

    // MARK: - deleteAllEmbeddings

    func testDeleteAllEmbeddingsClearsTable() throws {
        let index = try freshIndex()
        _ = try writeNote("x.md", body: "x")
        index.indexAllFiles()
        let x = try XCTUnwrap(index.file(forRelativePath: "x.md"))
        try index.upsertEmbedding(fileID: x.id, contentHash: x.contentHash,
                                  vector: [1, 2], modelVersion: 1)

        try index.deleteAllEmbeddings()

        XCTAssertNil(try index.embedding(forFileID: x.id))
        XCTAssertEqual(try index.embeddingsMissingOrStale(modelVersion: 1).map(\.path), ["x.md"])
    }
}
