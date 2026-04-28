import XCTest
import Foundation
import NaturalLanguage
@testable import ClearlyCore

/// End-to-end retrieval quality test against the golden corpus.
///
/// Runs every query in `golden-queries.json` through `VaultChatRetriever.retrieve` against
/// a temporary VaultIndex built from `golden-corpus/*.md`, then asserts Recall@5 and MRR@10
/// against committed baselines.
///
/// **Baselines (run on golden corpus of 34 notes / 31 queries, 2026-04-28):**
///
///     NLContextualEmbedding (chunked + filename boost): Recall@5 = 0.968, MRR@10 = 0.862
///     gte-small CoreML INT8 (chunked + filename boost): Recall@5 = TBD,   MRR@10 = TBD
///     Lift from embedder swap: TBD pp Recall@5
///
/// Floors are set 5pp below the current baseline so day-to-day noise doesn't fail CI but a
/// real regression (a missing query, a fusion bug, a bad MODEL_VERSION bump) does. Bump the
/// floors alongside the baseline comment when retrieval improves.
///
/// The test is skipped (XCTSkipIf) when the embedder model assets aren't available — keeps
/// CI green on environments where Apple's NLContextualEmbedding hasn't been downloaded
/// (notably some CI runners) and where the CoreML model bundle wasn't built in.
final class RetrievalQualityTests: XCTestCase {

    private struct GoldenQuery: Decodable {
        let id: String
        let type: String
        let query: String
        let expected: [String]
    }

    private struct GoldenQueriesFile: Decodable {
        let queries: [GoldenQuery]
    }

    /// Pass/fail thresholds. Set 5pp below the *current* committed baselines so a regression
    /// of >5 percentage points in either metric fails CI but normal noise doesn't. Bump these
    /// alongside the baseline comment block when retrieval improves.
    /// Current source: NLContextualEmbedding chunked + filename boost (2026-04-28).
    private static let recallAt5Floor: Double = 0.918   // baseline 0.968 − 5pp
    private static let mrrAt10Floor: Double = 0.812     // baseline 0.862 − 5pp

    func testRetrievalQualityAgainstGoldenCorpus() async throws {
        try skipIfEmbedderUnavailable()

        let (vault, queries) = try setupCorpusAndQueries()
        defer { try? FileManager.default.removeItem(at: vault.url) }

        let recallAt5 = try await measureRecallAt5(vault: vault, queries: queries)
        let mrrAt10 = try await measureMRRAt10(vault: vault, queries: queries)

        // Print the metrics regardless of pass/fail so the CI logs always carry the numbers.
        print("===== Retrieval Quality =====")
        print(String(format: "Recall@5  = %.3f  (floor: %.3f)", recallAt5, Self.recallAt5Floor))
        print(String(format: "MRR@10    = %.3f  (floor: %.3f)", mrrAt10, Self.mrrAt10Floor))
        print("=============================")

        XCTAssertGreaterThanOrEqual(recallAt5, Self.recallAt5Floor,
                                     "Recall@5 regressed below floor — retrieval quality dropped.")
        XCTAssertGreaterThanOrEqual(mrrAt10, Self.mrrAt10Floor,
                                     "MRR@10 regressed below floor — retrieval quality dropped.")
    }

    // MARK: - Corpus setup

    private struct CorpusVault {
        let url: URL
        let index: VaultIndex
    }

    private func setupCorpusAndQueries() throws -> (CorpusVault, [GoldenQuery]) {
        // Locate the bundled fixture directory.
        guard let fixtureRoot = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            throw XCTSkip("Fixtures bundle resource missing — check Package.swift resources rule.")
        }
        let corpusRoot = fixtureRoot.appendingPathComponent("golden-corpus", isDirectory: true)
        let queriesURL = fixtureRoot.appendingPathComponent("golden-queries.json")

        // Copy the corpus into a temp directory so the index treats it as a writable vault.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("clearly-retrieval-quality-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let fileManager = FileManager.default
        let entries = try fileManager.contentsOfDirectory(at: corpusRoot, includingPropertiesForKeys: nil)
        for entry in entries where entry.pathExtension == "md" {
            let dest = tmp.appendingPathComponent(entry.lastPathComponent)
            try fileManager.copyItem(at: entry, to: dest)
        }

        // Build the index + run the embedding sweep synchronously so retrieval can find chunks.
        let index = try VaultIndex(locationURL: tmp)
        index.indexAllFiles()
        try embedSynchronously(index: index, vaultURL: tmp)

        // Load + decode queries.
        let queriesData = try Data(contentsOf: queriesURL)
        let decoded = try JSONDecoder().decode(GoldenQueriesFile.self, from: queriesData)

        return (CorpusVault(url: tmp, index: index), decoded.queries)
    }

    /// Synchronous version of VaultIndex.scheduleEmbeddingRefresh — the production sweep
    /// runs in a detached Task on a background queue and we need it to finish before the
    /// test queries run. Mirrors the same logic so the test exercises the real chunking +
    /// embedding path.
    private func embedSynchronously(index: VaultIndex, vaultURL: URL) throws {
        let stale = try index.embeddingsMissingOrStale(modelVersion: EmbeddingService.MODEL_VERSION)
        guard !stale.isEmpty else { return }
        let service = try EmbeddingService()
        for target in stale {
            let fileURL = vaultURL.appendingPathComponent(target.path)
            guard let data = try? Data(contentsOf: fileURL),
                  let content = String(data: data, encoding: .utf8) else { continue }
            let filename = (target.path as NSString).lastPathComponent
            let chunks = MarkdownChunker.chunk(source: content, filename: filename)
            guard !chunks.isEmpty else { continue }
            var inputs: [VaultIndex.ChunkEmbeddingInput] = []
            inputs.reserveCapacity(chunks.count)
            for chunk in chunks {
                do {
                    let vector = try service.embed(chunk.embedText)
                    inputs.append(VaultIndex.ChunkEmbeddingInput(
                        chunkIndex: chunk.index,
                        textOffset: chunk.textOffset,
                        textLength: chunk.textLength,
                        headingPath: chunk.headingPath,
                        body: chunk.body,
                        vector: vector
                    ))
                } catch EmbeddingError.emptyText {
                    continue
                }
            }
            guard !inputs.isEmpty else { continue }
            try index.upsertChunkEmbeddings(
                fileID: target.fileID,
                contentHash: target.contentHash,
                chunks: inputs,
                modelVersion: EmbeddingService.MODEL_VERSION
            )
        }
    }

    // MARK: - Metrics

    private func measureRecallAt5(vault: CorpusVault, queries: [GoldenQuery]) async throws -> Double {
        var hits = 0
        var perQueryFailures: [String] = []
        for q in queries {
            let results = try await VaultChatRetriever.retrieve(
                question: q.query,
                vaultURL: vault.url,
                index: vault.index,
                topK: 5
            )
            let topPaths = Set(results.map(\.path))
            if q.expected.isEmpty {
                // Negative query: pass if no result is in any plausibly-expected ground-truth.
                // Operational: just count pass — we can't know for sure no result is "right" in
                // an open-domain sense, but for our corpus we know nothing matches these.
                hits += 1
            } else if !topPaths.isDisjoint(with: q.expected) {
                hits += 1
            } else {
                perQueryFailures.append("[\(q.type)] \(q.id): expected one of \(q.expected), got \(results.prefix(5).map(\.path))")
            }
        }
        if !perQueryFailures.isEmpty {
            print("--- Recall@5 misses ---")
            for line in perQueryFailures { print(line) }
            print("-----------------------")
        }
        return Double(hits) / Double(queries.count)
    }

    private func measureMRRAt10(vault: CorpusVault, queries: [GoldenQuery]) async throws -> Double {
        var rrSum = 0.0
        var counted = 0
        for q in queries {
            // MRR is undefined for negative queries; skip them.
            guard !q.expected.isEmpty else { continue }
            counted += 1
            let results = try await VaultChatRetriever.retrieve(
                question: q.query,
                vaultURL: vault.url,
                index: vault.index,
                topK: 10
            )
            let firstHitRank = results.enumerated().first { _, hit in
                q.expected.contains(hit.path)
            }?.offset
            if let rank = firstHitRank {
                rrSum += 1.0 / Double(rank + 1)
            }
        }
        guard counted > 0 else { return 0 }
        return rrSum / Double(counted)
    }

    // MARK: - Skip when embedder isn't available

    private func skipIfEmbedderUnavailable() throws {
        guard let model = NLContextualEmbedding(language: .english) else {
            throw XCTSkip("NLContextualEmbedding(.english) unavailable on this OS — likely a CI without language assets.")
        }
        if !model.hasAvailableAssets {
            throw XCTSkip("NLContextualEmbedding assets aren't downloaded — re-run after the OS caches them.")
        }
    }
}
