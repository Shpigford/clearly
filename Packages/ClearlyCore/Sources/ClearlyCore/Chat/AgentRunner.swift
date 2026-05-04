import Foundation

/// The single entry point to an LLM agent. Implemented by the local CLI
/// runners (Claude Code, Codex). V1 is request / response; streaming +
/// multi-turn tool use come later.
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
}
