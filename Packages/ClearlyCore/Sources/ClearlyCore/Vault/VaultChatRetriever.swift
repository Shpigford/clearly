import Foundation

/// Pulls the most relevant note chunks for a chat question out of the vault, in process —
/// no MCP subprocess, no agent tool calls. The chat coordinator stuffs the returned chunks
/// into the prompt and asks the LLM to answer over them (RAG). Switching to in-process
/// retrieval avoids the App Sandbox blocking subprocesses + git probes, and the chunked
/// retrieval keeps the synonym/related-word matching that made the old MCP semantic_search
/// useful — we use the same `EmbeddingService` + chunk embeddings primitives, just directly
/// instead of via an external tool round-trip.
///
/// Hybrid retrieval: three signals fused via reciprocal-rank-fusion.
///   1. **Cosine over chunk embeddings** — semantic match.
///   2. **bm25 over chunks_fts** — literal keyword match (catches title hits the embedder
///      misses, e.g. "writing on local-first software" → `Local-First Software.md`).
///   3. **Filename / heading boost** — chunks whose filename or any heading in their path
///      contains a non-stopword query keyword get a virtual rank-0 hit. Cheap and
///      predictable; only fires for keywords longer than 3 chars to avoid false positives.
public enum VaultChatRetriever {

    public struct Hit: Equatable {
        public let path: String           // vault-relative
        public let filename: String       // extension-stripped, suitable for [[wiki-link]]
        public let headingPath: [String]  // section nesting at the chunk's location
        public let score: Float
        public let content: String        // chunk body (not the whole note)

        public init(
            path: String,
            filename: String,
            headingPath: [String],
            score: Float,
            content: String
        ) {
            self.path = path
            self.filename = filename
            self.headingPath = headingPath
            self.score = score
            self.content = content
        }
    }

    /// Per-chunk body cap. Chunks are typically <2KB but a frontmatter-only or runaway
    /// markdown file might overflow; clamp so the LLM context stays predictable.
    public static let maxBytesPerChunk = 6_000

    /// How many chunks we hand to the LLM. After dedupe-by-file, this is also the file
    /// count cap. Tuned for "thousands of notes, answer over the most-relevant handful" —
    /// beyond ~10 the marginal note is rarely cited and just inflates the prompt.
    public static let defaultTopK = 10

    /// How deep to look in each ranking source before fusion. We pull more than we'll keep
    /// so RRF has room to promote a chunk that ranks merely "decent" in both signals over
    /// one that ranks #1 in only one.
    public static let fusionPoolSize = 30

    /// RRF damping constant. The canonical value from Cormack et al. is 60, but that's
    /// tuned for IR benchmarks where rankings are similarly noisy. Apple's small mean-pooled
    /// embedder is much weaker than bm25 at literal title matches, so we use a tighter k=10
    /// to give #1 in any one method enough weight to stay in the top-K — otherwise a vault
    /// full of demo notes can crowd out a perfectly titled match. Verified manually against
    /// the Documents-vault demo content; revisit if a multilingual or larger embedder lands.
    private static let rrfK: Double = 10

    /// Minimum keyword length for filename/heading boost. Shorter words are too generic
    /// (a file called "notes.md" would otherwise boost on every "notes" query).
    private static let minBoostKeywordLength = 4

    public static func retrieve(
        question: String,
        vaultURL: URL,
        index: VaultIndex,
        topK: Int = defaultTopK
    ) async throws -> [Hit] {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // 1. Semantic ranking: cosine over chunk embeddings.
        let service = try EmbeddingService()
        let queryVector = try service.embed(trimmed)
        let stored = try index.allChunkEmbeddings(modelVersion: EmbeddingService.MODEL_VERSION)

        struct ChunkRef: Hashable {
            let path: String
            let chunkIndex: Int
        }

        // Hold every chunk we considered, keyed by its (path, chunkIndex) tuple. Used to
        // hydrate the final Hit values with the actual chunk body + heading path after
        // fusion picks winners.
        var chunkBank: [ChunkRef: VaultIndex.StoredChunkEmbedding] = [:]
        var cosineScored: [(ref: ChunkRef, score: Float)] = []
        cosineScored.reserveCapacity(stored.count)
        for entry in stored {
            guard entry.vector.count == queryVector.count else { continue }
            let ref = ChunkRef(path: entry.path, chunkIndex: entry.chunkIndex)
            chunkBank[ref] = entry
            let score = EmbeddingService.cosine(queryVector, entry.vector)
            cosineScored.append((ref, score))
        }
        cosineScored.sort { $0.score > $1.score }

        var semanticRank: [ChunkRef: Int] = [:]
        for (rank, hit) in cosineScored.prefix(fusionPoolSize).enumerated() {
            semanticRank[hit.ref] = rank
        }

        // 2. Keyword ranking: bm25 over chunks_fts.
        let keywords = extractKeywords(from: trimmed)
        var keywordRank: [ChunkRef: Int] = [:]
        if !keywords.isEmpty {
            let ftsResults = index.searchByKeywords(keywords, limit: fusionPoolSize)
            for (rank, result) in ftsResults.enumerated() {
                let ref = ChunkRef(path: result.path, chunkIndex: result.chunkIndex)
                keywordRank[ref] = rank
            }
        }

        // 3. Filename / heading boost: any chunk whose filename or heading path contains a
        //    meaningful query keyword (length ≥ 4) gets a virtual rank-0 hit. Filtering by
        //    length avoids common short words ("note", "file", "page") triggering boosts.
        let boostKeywords = keywords.filter { $0.count >= minBoostKeywordLength }
        var boostRank: [ChunkRef: Int] = [:]
        if !boostKeywords.isEmpty {
            for (ref, entry) in chunkBank {
                let filename = URL(fileURLWithPath: entry.path)
                    .deletingPathExtension()
                    .lastPathComponent
                    .lowercased()
                let headingsLower = entry.headingPath.map { $0.lowercased() }
                let isMatch = boostKeywords.contains { keyword in
                    filename.contains(keyword) || headingsLower.contains { $0.contains(keyword) }
                }
                if isMatch {
                    boostRank[ref] = 0
                }
            }
        }

        // 4. RRF fusion across three streams: score(c) = Σ_method 1 / (k + rank(c)).
        let allRefs = Set(semanticRank.keys)
            .union(keywordRank.keys)
            .union(boostRank.keys)
        var fused: [(ref: ChunkRef, score: Double)] = []
        fused.reserveCapacity(allRefs.count)
        for ref in allRefs {
            var score = 0.0
            if let rank = semanticRank[ref] { score += 1.0 / (rrfK + Double(rank)) }
            if let rank = keywordRank[ref] { score += 1.0 / (rrfK + Double(rank)) }
            if let rank = boostRank[ref] { score += 1.0 / (rrfK + Double(rank)) }
            fused.append((ref, score))
        }
        fused.sort { $0.score > $1.score }

        // 5. Dedupe by file path. Multiple chunks of the same long note shouldn't crowd
        //    out other relevant notes — keep the highest-scoring chunk per file.
        var seenPaths = Set<String>()
        var dedupedChunkRefs: [(ref: ChunkRef, score: Double)] = []
        for entry in fused {
            if seenPaths.insert(entry.ref.path).inserted {
                dedupedChunkRefs.append(entry)
                if dedupedChunkRefs.count >= topK { break }
            }
        }

        // 6. Hydrate hits. Pull chunk body from the chunkBank when available, else fall back
        //    to reading the file (FTS-only hits aren't in chunkBank since cosine never saw
        //    them). On fallback we read the file once and slice out the chunk's byte range.
        return dedupedChunkRefs.compactMap { entry -> Hit? in
            let ref = entry.ref
            let filename = URL(fileURLWithPath: ref.path)
                .deletingPathExtension()
                .lastPathComponent

            if let stored = chunkBank[ref] {
                let body = chunkBody(for: stored, vaultURL: vaultURL)
                guard !body.isEmpty else { return nil }
                return Hit(
                    path: ref.path,
                    filename: filename,
                    headingPath: stored.headingPath,
                    score: Float(entry.score),
                    content: clamp(body)
                )
            }
            // FTS-only path: chunkBank doesn't have this ref because the cosine pool didn't
            // surface it. Fall back to a per-file lookup of all stored chunks.
            guard let chunks = try? index.chunkEmbeddings(forFileID: lookupFileID(forPath: ref.path, in: index)),
                  let stored = chunks.first(where: { $0.chunkIndex == ref.chunkIndex }) else {
                return nil
            }
            let body = chunkBody(for: stored, vaultURL: vaultURL)
            guard !body.isEmpty else { return nil }
            return Hit(
                path: ref.path,
                filename: filename,
                headingPath: stored.headingPath,
                score: Float(entry.score),
                content: clamp(body)
            )
        }
    }

    /// Extract a chunk's body string by reading the source file and slicing the recorded
    /// byte range. Caching is unnecessary — the read happens at most `topK` times per
    /// query and OS file caches absorb the cost.
    private static func chunkBody(
        for stored: VaultIndex.StoredChunkEmbedding,
        vaultURL: URL
    ) -> String {
        let absURL = vaultURL.appendingPathComponent(stored.path)
        guard let data = try? Data(contentsOf: absURL) else { return "" }
        let start = max(0, min(stored.textOffset, data.count))
        let end = max(start, min(stored.textOffset + stored.textLength, data.count))
        let slice = data.subdata(in: start..<end)
        return String(data: slice, encoding: .utf8) ?? ""
    }

    private static func clamp(_ body: String) -> String {
        guard body.count > maxBytesPerChunk else { return body }
        return String(body.prefix(maxBytesPerChunk)) + "\n\n…[truncated]"
    }

    private static func lookupFileID(forPath path: String, in index: VaultIndex) -> Int64 {
        return index.file(forRelativePath: path)?.id ?? -1
    }

    /// Extract content-bearing tokens from the user's question for FTS5 keyword search and
    /// filename/heading boost. Drops common English stopwords and one-character fragments;
    /// lowercases and splits on punctuation/whitespace. Hyphenated terms keep both the
    /// joined form and the parts so "local-first" matches notes containing either "local-first"
    /// or "local first".
    public static func extractKeywords(from question: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ",.!?;:()[]{}\"'`"))
        let raw = question
            .lowercased()
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var tokens: [String] = []
        for word in raw {
            guard word.count > 1, !Self.stopwords.contains(word) else { continue }
            if seen.insert(word).inserted {
                tokens.append(word)
            }
            if word.contains("-") {
                for part in word.split(separator: "-") {
                    let s = String(part)
                    guard s.count > 1, !Self.stopwords.contains(s) else { continue }
                    if seen.insert(s).inserted { tokens.append(s) }
                }
            }
        }
        return Array(tokens.prefix(12))
    }

    private static let stopwords: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could",
        "should", "may", "might", "must", "shall", "of", "in", "to", "for",
        "with", "from", "by", "on", "at", "as", "and", "or", "but", "not",
        "no", "if", "then", "than", "so", "such", "this", "that", "these",
        "those", "my", "your", "their", "our", "his", "her", "its", "we",
        "you", "they", "i", "me", "him", "us", "them", "what", "which",
        "when", "where", "why", "how", "who", "whom", "whose", "about",
        "into", "out", "up", "down", "over", "under", "again", "further",
        "very", "can", "just", "only", "also", "any", "some", "all", "more",
        "most", "other", "another", "each", "every", "both", "either",
        "neither", "much", "many", "few", "lot", "lots"
    ]

    /// Render hits into the markdown block we splice into the chat prompt as `{{vault_state}}`.
    /// Each hit shows the wiki-link citation, an optional heading-path breadcrumb so the LLM
    /// knows where in the note this chunk lives, and the chunk body.
    public static func renderContextBlock(_ hits: [Hit]) -> String {
        guard !hits.isEmpty else {
            return "_(No notes matched this question. Answer from general knowledge if you can; otherwise say so.)_"
        }
        var sections: [String] = ["# Relevant notes"]
        for hit in hits {
            sections.append("")
            if hit.headingPath.isEmpty {
                sections.append("## [[\(hit.filename)]]")
            } else {
                let breadcrumb = hit.headingPath.joined(separator: " → ")
                sections.append("## [[\(hit.filename)]] · \(breadcrumb)")
            }
            sections.append("")
            sections.append("`\(hit.path)`")
            sections.append("")
            sections.append(hit.content)
        }
        return sections.joined(separator: "\n")
    }
}
