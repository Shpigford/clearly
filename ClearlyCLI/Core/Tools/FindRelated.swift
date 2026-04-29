import Foundation
import ClearlyCore

struct FindRelatedArgs: Codable {
    let relativePath: String
    let limit: Int?
    let vault: String?
}

struct FindRelatedResult: Codable {
    struct Hit: Codable {
        let vault: String
        let vaultPath: String
        let relativePath: String
        let filename: String
        let score: Float
    }
    let vault: String
    let source: String
    let totalCount: Int
    let returnedCount: Int
    let results: [Hit]
}

/// "Notes related to this one." Reuses the existing chunk embeddings —
/// loads every chunk from the source file, takes their mean vector, and
/// scores it against every other file's chunks via cosine. Best score
/// per file, source excluded, descending by similarity.
///
/// English-only by virtue of the underlying embedding service. Files
/// whose chunks are missing or stale (model version mismatch) are
/// silently skipped on both sides — no separate error.
func findRelated(_ args: FindRelatedArgs, vaults: [LoadedVault]) async throws -> FindRelatedResult {
    guard !args.relativePath.isEmpty else {
        throw ToolError.missingArgument("relative_path")
    }
    if let raw = args.limit, raw <= 0 {
        throw ToolError.invalidArgument(name: "limit", reason: "must be greater than 0")
    }
    let limit = min(args.limit ?? 10, 50)

    let sourceVault: LoadedVault
    switch try VaultResolver.resolve(relativePath: args.relativePath, hint: args.vault, in: vaults) {
    case .notFound:
        throw ToolError.noteNotFound(args.relativePath)
    case .ambiguous(let matches):
        throw ToolError.ambiguousVault(
            relativePath: args.relativePath,
            matches: matches.map { $0.url.lastPathComponent }
        )
    case .resolved(let v):
        sourceVault = v
    }

    guard let sourceFile = sourceVault.index.file(forRelativePath: args.relativePath) else {
        throw ToolError.noteNotFound(args.relativePath)
    }

    let sourceChunks = try sourceVault.index.chunkEmbeddings(forFileID: sourceFile.id)
    guard let queryVector = meanVector(of: sourceChunks.map(\.vector)) else {
        return FindRelatedResult(
            vault: sourceVault.url.lastPathComponent,
            source: args.relativePath,
            totalCount: 0,
            returnedCount: 0,
            results: []
        )
    }

    // Optional vault narrowing — same convention as semantic_search:
    // substring match on path or basename.
    let candidateVaults: [LoadedVault]
    if let filter = args.vault, !filter.isEmpty {
        let lower = filter.lowercased()
        candidateVaults = vaults.filter {
            $0.url.path.lowercased().contains(lower) || $0.url.lastPathComponent.lowercased().contains(lower)
        }
    } else {
        candidateVaults = vaults
    }

    var bestPerFile: [String: (vault: LoadedVault, path: String, score: Float)] = [:]
    for vault in candidateVaults {
        let stored = try vault.index.allChunkEmbeddings(modelVersion: EmbeddingService.MODEL_VERSION)
        for entry in stored {
            // Skip the source itself. Match on (vault path, relative path)
            // so two vaults with same-named files don't cross-contaminate.
            if vault.url.path == sourceVault.url.path && entry.path == sourceFile.path {
                continue
            }
            guard entry.vector.count == queryVector.count else { continue }
            let score = EmbeddingService.cosine(queryVector, entry.vector)
            let key = "\(vault.url.path)\u{0}\(entry.path)"
            if let prev = bestPerFile[key], prev.score >= score { continue }
            bestPerFile[key] = (vault, entry.path, score)
        }
    }

    let scored = bestPerFile.values.sorted { $0.score > $1.score }
    let capped = Array(scored.prefix(limit))
    let hits = capped.map { item -> FindRelatedResult.Hit in
        let filename = URL(fileURLWithPath: item.path).deletingPathExtension().lastPathComponent
        return FindRelatedResult.Hit(
            vault: item.vault.url.lastPathComponent,
            vaultPath: item.vault.url.path,
            relativePath: item.path,
            filename: filename,
            score: item.score
        )
    }

    return FindRelatedResult(
        vault: sourceVault.url.lastPathComponent,
        source: args.relativePath,
        totalCount: scored.count,
        returnedCount: hits.count,
        results: hits
    )
}

private func meanVector(of vectors: [[Float]]) -> [Float]? {
    guard let first = vectors.first, !first.isEmpty else { return nil }
    let dims = first.count
    var sum = [Float](repeating: 0, count: dims)
    var count: Int = 0
    for vec in vectors where vec.count == dims {
        for i in 0..<dims { sum[i] += vec[i] }
        count += 1
    }
    guard count > 0 else { return nil }
    let inv = 1 / Float(count)
    return sum.map { $0 * inv }
}
