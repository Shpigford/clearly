import XCTest
import NaturalLanguage
@testable import ClearlyCore

final class EmbeddingServiceTests: XCTestCase {

    // MARK: - Cosine (pure math, no model needed)

    func testCosineIdenticalIsOne() {
        let a: [Float] = [1, 2, 3, 4]
        XCTAssertEqual(EmbeddingService.cosine(a, a), 1.0, accuracy: 1e-5)
    }

    func testCosineOrthogonalIsZero() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [0, 1, 0]
        XCTAssertEqual(EmbeddingService.cosine(a, b), 0.0, accuracy: 1e-5)
    }

    func testCosineOppositeIsNegativeOne() {
        let a: [Float] = [1, 2, 3]
        let b: [Float] = [-1, -2, -3]
        XCTAssertEqual(EmbeddingService.cosine(a, b), -1.0, accuracy: 1e-5)
    }

    func testCosineHandlesZeroVectorWithoutNaN() {
        let a: [Float] = [0, 0, 0]
        let b: [Float] = [1, 2, 3]
        let c = EmbeddingService.cosine(a, b)
        XCTAssertFalse(c.isNaN)
        XCTAssertEqual(c, 0)
    }

    // MARK: - BLOB round-trip

    func testBlobDataRoundTrip() {
        let original: [Float] = [0.0, 1.5, -2.25, .pi, .infinity, -.infinity, 1e-30]
        let blob = original.blobData
        XCTAssertEqual(blob.count, original.count * MemoryLayout<Float>.size)
        let recovered = [Float].fromBlobData(blob)
        XCTAssertEqual(recovered, original)
    }

    func testBlobDataRejectsMisalignedSize() {
        let bad = Data([0x00, 0x01, 0x02])  // not a multiple of 4
        XCTAssertNil([Float].fromBlobData(bad))
    }

    // MARK: - Live model (skip when assets aren't on the runner)

    private func makeServiceOrSkip() throws -> EmbeddingService {
        // Probe asset availability without triggering a download. NLContextualEmbedding(language:)
        // is the same factory the service uses.
        guard let probe = NLContextualEmbedding(language: .english), probe.hasAvailableAssets else {
            throw XCTSkip("NLContextualEmbedding English assets not available on this runner")
        }
        return try EmbeddingService()
    }

    func testEmbedIdenticalTextProducesIdenticalVectors() throws {
        let service = try makeServiceOrSkip()
        let text = "The quick brown fox jumps over the lazy dog."
        let v1 = try service.embed(text)
        let v2 = try service.embed(text)
        XCTAssertEqual(v1.count, v2.count)
        XCTAssertGreaterThan(v1.count, 0)
        XCTAssertEqual(EmbeddingService.cosine(v1, v2), 1.0, accuracy: 1e-4)
    }

    func testEmbedSimilarTextIsHighlySimilar() throws {
        let service = try makeServiceOrSkip()
        // Whitespace + casing should barely move the vector.
        let v1 = try service.embed("The quick brown fox jumps over the lazy dog.")
        let v2 = try service.embed("  The   quick brown fox JUMPS over   the lazy dog.  ")
        XCTAssertGreaterThan(EmbeddingService.cosine(v1, v2), 0.95)
    }

    func testEmbedUnrelatedTextHasLowerSimilarity() throws {
        let service = try makeServiceOrSkip()
        let v1 = try service.embed("Deep work and the practice of intense, distraction-free concentration.")
        let v2 = try service.embed("Recipe for sourdough starter using rye flour and warm water.")
        let related = try service.embed("Cultivating focused attention while writing software.")

        let unrelatedScore = EmbeddingService.cosine(v1, v2)
        let relatedScore = EmbeddingService.cosine(v1, related)
        // Topical match should outscore the unrelated pair by a clear margin.
        XCTAssertGreaterThan(relatedScore, unrelatedScore)
    }

    func testEmbedEmptyTextThrows() throws {
        let service = try makeServiceOrSkip()
        XCTAssertThrowsError(try service.embed("   \n  ")) { error in
            XCTAssertEqual(error as? EmbeddingError, .emptyText)
        }
    }

    func testEmbedDimensionMatchesModel() throws {
        let service = try makeServiceOrSkip()
        let v = try service.embed("hello world")
        XCTAssertEqual(v.count, service.dimension)
        XCTAssertGreaterThan(v.count, 0)
    }
}
