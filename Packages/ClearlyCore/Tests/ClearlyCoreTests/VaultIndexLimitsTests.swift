import XCTest
@testable import ClearlyCore

final class VaultIndexLimitsTests: XCTestCase {

    private var tempVault: URL!

    override func setUpWithError() throws {
        tempVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-index-limits-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempVault, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempVault)
    }

    func testUpdateFileRemovesPreviouslyIndexedFileWhenItGrowsPastLimit() throws {
        let index = try VaultIndex(locationURL: tempVault)
        let noteURL = try writeNote("big.md", body: "# Big\n\nneedle #tag")
        index.indexAllFiles()
        let indexed = try XCTUnwrap(index.file(forRelativePath: "big.md"))
        try index.upsertChunkEmbeddings(
            fileID: indexed.id,
            contentHash: indexed.contentHash,
            chunks: [VaultIndex.ChunkEmbeddingInput(
                chunkIndex: 0,
                textOffset: 0,
                textLength: 6,
                headingPath: [],
                body: "needle",
                vector: [1]
            )],
            modelVersion: 1
        )

        try makeOversized(noteURL)
        let updated = try index.updateFile(at: "big.md")

        XCTAssertNil(updated)
        XCTAssertNil(index.file(forRelativePath: "big.md"))
        XCTAssertEqual(index.searchFiles(query: "needle").count, 0)
        XCTAssertEqual(index.searchByKeywords(["needle"], modelVersion: 1).count, 0)
        XCTAssertEqual(index.allTags().count, 0)
    }

    func testIndexAllFilesRemovesPreviouslyIndexedFileWhenItGrowsPastLimit() throws {
        let index = try VaultIndex(locationURL: tempVault)
        let noteURL = try writeNote("big.md", body: "# Big\n\nneedle")
        index.indexAllFiles()
        XCTAssertNotNil(index.file(forRelativePath: "big.md"))

        try makeOversized(noteURL)
        index.indexAllFiles()

        XCTAssertNil(index.file(forRelativePath: "big.md"))
        XCTAssertEqual(index.searchFiles(query: "needle").count, 0)
    }

    private func writeNote(_ name: String, body: String) throws -> URL {
        let url = tempVault.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeOversized(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(Limits.maxOpenableFileSize + 1))
        try handle.close()
    }
}
