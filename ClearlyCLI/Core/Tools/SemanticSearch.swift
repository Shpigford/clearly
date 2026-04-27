import Foundation
import ClearlyCore

struct SemanticSearchArgs: Codable {
    let query: String
    let limit: Int?
    let vault: String?
}

struct SemanticSearchResult: Codable {
    struct Hit: Codable {
        let vault: String
        let vaultPath: String
        let relativePath: String
        let filename: String
        let score: Float
        let snippet: String
    }
    let query: String
    let totalCount: Int
    let returnedCount: Int
    let results: [Hit]
}

func semanticSearch(_ args: SemanticSearchArgs, vaults: [LoadedVault]) async throws -> SemanticSearchResult {
    guard !args.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ToolError.missingArgument("query")
    }
    if let rawLimit = args.limit, rawLimit <= 0 {
        throw ToolError.invalidArgument(name: "limit", reason: "must be greater than 0")
    }
    let limit = min(args.limit ?? 10, 50)

    // Optional vault filter — same convention as get_backlinks: substring match on path or name.
    let candidateVaults: [LoadedVault]
    if let filter = args.vault, !filter.isEmpty {
        let lower = filter.lowercased()
        candidateVaults = vaults.filter {
            $0.url.path.lowercased().contains(lower) || $0.url.lastPathComponent.lowercased().contains(lower)
        }
    } else {
        candidateVaults = vaults
    }

    let service = try EmbeddingService()
    let queryVector = try service.embed(args.query)

    var scored: [(vault: LoadedVault, path: String, score: Float)] = []
    for vault in candidateVaults {
        let stored = try vault.index.allEmbeddings(modelVersion: EmbeddingService.MODEL_VERSION)
        for entry in stored {
            // Defensive: stored vectors with unexpected dim are skipped, not crashed against.
            guard entry.vector.count == queryVector.count else { continue }
            let score = EmbeddingService.cosine(queryVector, entry.vector)
            scored.append((vault, entry.path, score))
        }
    }
    scored.sort { $0.score > $1.score }

    let capped = Array(scored.prefix(limit))
    let hits = capped.map { item -> SemanticSearchResult.Hit in
        let absURL = item.vault.url.appendingPathComponent(item.path)
        let snippet = snippetFor(absoluteURL: absURL)
        // Match `search_notes` convention: extension-stripped (e.g. "deep-work" not
        // "deep-work.md") so the agent can hand it straight to a `[[wiki-link]]` resolver.
        let filename = URL(fileURLWithPath: item.path).deletingPathExtension().lastPathComponent
        return SemanticSearchResult.Hit(
            vault: item.vault.url.lastPathComponent,
            vaultPath: item.vault.url.path,
            relativePath: item.path,
            filename: filename,
            score: item.score,
            snippet: snippet
        )
    }

    return SemanticSearchResult(
        query: args.query,
        totalCount: scored.count,
        returnedCount: hits.count,
        results: hits
    )
}

/// Lightweight preview snippet — strips a leading YAML frontmatter block, then returns the first
/// non-empty paragraph clamped to ~200 characters. Best-effort; returns "" if the file isn't
/// readable so the tool result is still useful for ranking even when one note has gone missing.
private func snippetFor(absoluteURL url: URL) -> String {
    guard let data = try? Data(contentsOf: url),
          let raw = String(data: data, encoding: .utf8) else { return "" }
    // Normalize CRLF/CR to LF so frontmatter and paragraph splits don't trip on `\r`-suffixed
    // fence lines.
    let normalized = raw
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    var body = normalized
    var lines = normalized.components(separatedBy: "\n")
    // Trim leading blank lines so a UTF-8 BOM or stray newline doesn't hide the fence.
    while let first = lines.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
        lines.removeFirst()
    }
    if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
        lines.removeFirst()
        if let endIdx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            lines.removeSubrange(0...endIdx)
            body = lines.joined(separator: "\n")
        }
    }
    // First non-empty paragraph.
    let para = body
        .components(separatedBy: "\n\n")
        .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
    let cleaned = para.replacingOccurrences(of: "\n", with: " ")
                       .trimmingCharacters(in: .whitespacesAndNewlines)
    if cleaned.count <= 200 { return cleaned }
    let cutoff = cleaned.index(cleaned.startIndex, offsetBy: 200)
    return String(cleaned[..<cutoff]) + "…"
}
