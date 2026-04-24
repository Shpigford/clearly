import Foundation

/// The single entry point to an LLM agent. Every tier (local Claude CLI,
/// BYOK Anthropic API, OpenAI-compatible) implements this. V1 is request /
/// response; streaming + multi-turn tool use come later when the recipes need
/// them.
public protocol AgentRunner: Sendable {
    /// Run a prompt and return the assistant's raw text plus token accounting.
    func run(prompt: String, model: String?) async throws -> AgentResult
}

public struct AgentResult: Sendable, Equatable {
    public let text: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let model: String

    public init(text: String, inputTokens: Int, outputTokens: Int, model: String) {
        self.text = text
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.model = model
    }
}

public enum AgentError: Error, Equatable, Sendable {
    case missingAPIKey
    case invalidResponse(String)
    case httpError(status: Int, body: String)
    case transport(String)
    case invalidWikiOperation(String)
}

// MARK: - WikiOperation parsing

public enum AgentResultParser {

    /// Extract the first `{...}` JSON object from `text` and decode it as a
    /// `WikiOperation`. The agent is instructed to return JSON only, but
    /// models occasionally slip in a prose prefix — pulling the first
    /// balanced object makes us resilient to that drift.
    public static func parseWikiOperation(from text: String, kind: OperationKind) throws -> WikiOperation {
        guard let jsonString = extractFirstJSONObject(in: text) else {
            throw AgentError.invalidWikiOperation("no JSON object found in response")
        }
        guard let data = jsonString.data(using: .utf8) else {
            throw AgentError.invalidWikiOperation("non-UTF8 JSON payload")
        }
        do {
            let partial = try JSONDecoder().decode(PartialOperation.self, from: data)
            let op = WikiOperation(
                kind: kind,
                title: partial.title,
                rationale: partial.rationale,
                changes: partial.changes
            )
            try op.validate()
            return op
        } catch let error as WikiOperationError {
            throw AgentError.invalidWikiOperation(String(describing: error))
        } catch {
            throw AgentError.invalidWikiOperation(String(describing: error))
        }
    }

    private struct PartialOperation: Decodable {
        let title: String
        let rationale: String
        let changes: [FileChange]
    }

    static func extractFirstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let ch = text[index]
            if escaped {
                escaped = false
            } else if ch == "\\" && inString {
                escaped = true
            } else if ch == "\"" {
                inString.toggle()
            } else if !inString {
                if ch == "{" { depth += 1 }
                else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(text[start...index])
                    }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
