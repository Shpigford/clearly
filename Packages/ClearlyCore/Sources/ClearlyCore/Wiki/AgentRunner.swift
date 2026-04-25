import Foundation

/// The single entry point to an LLM agent. Implemented by the local CLI
/// runners (Claude Code today, Codex tomorrow). V1 is request / response;
/// streaming + multi-turn tool use come later when the recipes need them.
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
    case invalidResponse(String)
    case httpError(status: Int, body: String)
    case transport(String)
    case invalidWikiOperation(String)
}

// MARK: - WikiOperation parsing

/// Raw proposal as decoded from the agent's JSON response, before we decide
/// whether to promote it to a full `WikiOperation`. An empty `changes` array
/// is a legitimate outcome for Query/Lint ("nothing to file" / "no issues
/// found"); callers handle the empty case specially instead of throwing.
public struct AgentProposal: Sendable, Equatable {
    public let title: String
    public let rationale: String
    public let changes: [FileChange]

    public init(title: String, rationale: String, changes: [FileChange]) {
        self.title = title
        self.rationale = rationale
        self.changes = changes
    }

    public var hasChanges: Bool { !changes.isEmpty }
}

public enum AgentResultParser {

    /// Extract the first `{...}` JSON object from `text` and decode it into
    /// an `AgentProposal`. Does NOT call `WikiOperation.validate()` — callers
    /// that want a staged operation call `toOperation(kind:)` on the
    /// proposal and handle validation / emptiness themselves.
    public static func parseProposal(from text: String) throws -> AgentProposal {
        guard let jsonString = extractFirstJSONObject(in: text) else {
            throw AgentError.invalidWikiOperation("no JSON object found in response")
        }
        guard let data = jsonString.data(using: .utf8) else {
            throw AgentError.invalidWikiOperation("non-UTF8 JSON payload")
        }
        do {
            let partial = try JSONDecoder().decode(PartialOperation.self, from: data)
            return AgentProposal(
                title: partial.title,
                rationale: partial.rationale,
                changes: partial.changes
            )
        } catch {
            throw AgentError.invalidWikiOperation(String(describing: error))
        }
    }

    /// Legacy shape — keep for existing callers that want a validated
    /// operation directly. New code should call `parseProposal` and decide
    /// how to handle empty / no-op outcomes.
    public static func parseWikiOperation(from text: String, kind: OperationKind) throws -> WikiOperation {
        let proposal = try parseProposal(from: text)
        let op = WikiOperation(
            kind: kind,
            title: proposal.title,
            rationale: proposal.rationale,
            changes: proposal.changes
        )
        do {
            try op.validate()
        } catch let error as WikiOperationError {
            throw AgentError.invalidWikiOperation(String(describing: error))
        }
        return op
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
