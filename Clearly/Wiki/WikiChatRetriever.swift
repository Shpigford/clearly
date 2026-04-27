import Foundation
import ClearlyCore

/// Pulls the most relevant notes for a chat question out of the vault, in
/// process — no MCP subprocess, no agent tool calls. The chat coordinator
/// stuffs the returned notes into the prompt and asks the LLM to answer
/// over them (RAG). Switching to this avoids the App Sandbox blocking
/// claude's MCP-server subprocess + git probes, and keeps the synonym /
/// related-word matching that made the old MCP semantic_search useful —
/// we use the same `EmbeddingService` + `allEmbeddings` primitives, just
/// directly instead of via an external tool round-trip.
enum WikiChatRetriever {

    struct Hit {
        let path: String     // vault-relative
        let filename: String // extension-stripped, suitable for [[wiki-link]]
        let score: Float
        let content: String  // truncated note body
    }

    /// Per-note body cap. Notes larger than this are truncated; the LLM
    /// gets enough to answer most questions without us blowing the prompt
    /// budget when the top hit is a long reference doc.
    static let maxBytesPerNote = 6_000

    /// How many notes we hand to the LLM. Tuned for "thousands of notes,
    /// answer over the most-relevant handful" — beyond ~10 the marginal
    /// note is rarely cited and just inflates the prompt.
    static let defaultTopK = 10

    /// Retrieve top-K semantically-relevant notes for `question` from the
    /// vault. Runs off the main actor — embedding model load + cosine over
    /// every stored vector is too long for the UI thread.
    static func retrieve(
        question: String,
        vaultURL: URL,
        index: VaultIndex,
        topK: Int = defaultTopK
    ) async throws -> [Hit] {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let service = try EmbeddingService()
        let queryVector = try service.embed(trimmed)
        let stored = try index.allEmbeddings(modelVersion: EmbeddingService.MODEL_VERSION)

        var scored: [(path: String, score: Float)] = []
        scored.reserveCapacity(stored.count)
        for entry in stored {
            guard entry.vector.count == queryVector.count else { continue }
            let score = EmbeddingService.cosine(queryVector, entry.vector)
            scored.append((entry.path, score))
        }
        scored.sort { $0.score > $1.score }

        let top = scored.prefix(topK)
        return top.compactMap { item -> Hit? in
            let absURL = vaultURL.appendingPathComponent(item.path)
            guard let data = try? Data(contentsOf: absURL),
                  let raw = String(data: data, encoding: .utf8) else { return nil }
            let body = raw.count > maxBytesPerNote
                ? String(raw.prefix(maxBytesPerNote)) + "\n\n…[truncated]"
                : raw
            let filename = URL(fileURLWithPath: item.path)
                .deletingPathExtension()
                .lastPathComponent
            return Hit(path: item.path, filename: filename, score: item.score, content: body)
        }
    }

    /// Render hits into the markdown block we splice into the chat prompt
    /// as `{{vault_state}}`. Headed `## [[note-name]]` so the LLM has the
    /// citation form sitting right next to each note's body.
    static func renderContextBlock(_ hits: [Hit]) -> String {
        guard !hits.isEmpty else {
            return "_(No notes matched this question. Answer from general knowledge if you can; otherwise say so.)_"
        }
        var sections: [String] = ["# Relevant notes"]
        for hit in hits {
            sections.append("")
            sections.append("## [[\(hit.filename)]]")
            sections.append("")
            sections.append("`\(hit.path)`")
            sections.append("")
            sections.append(hit.content)
        }
        return sections.joined(separator: "\n")
    }
}
