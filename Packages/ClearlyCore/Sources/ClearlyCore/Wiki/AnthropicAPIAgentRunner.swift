import Foundation

/// BYOK runner that talks directly to Anthropic's Messages API. The API key
/// is read from KeychainStore each call so the user can rotate without
/// restarting the app. Default model is claude-sonnet-4-6 — fast enough for
/// interactive ingest/query/lint, cheap enough for the cost meter.
public struct AnthropicAPIAgentRunner: AgentRunner, Sendable {
    public static let defaultModel = "claude-sonnet-4-6"
    public static let apiVersion = "2023-06-01"

    public let keychain: KeychainStore
    public let keychainAccount: String
    public let baseURL: URL
    public let session: URLSession

    public init(
        keychain: KeychainStore = KeychainStore(),
        keychainAccount: String = WikiKeychainAccount.anthropicAPIKey,
        baseURL: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        session: URLSession = .shared
    ) {
        self.keychain = keychain
        self.keychainAccount = keychainAccount
        self.baseURL = baseURL
        self.session = session
    }

    public func run(prompt: String, model: String?) async throws -> AgentResult {
        guard let apiKey = try keychain.get(keychainAccount), !apiKey.isEmpty else {
            throw AgentError.missingAPIKey
        }

        let modelID = model ?? Self.defaultModel
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

        let payload: [String: Any] = [
            "model": modelID,
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": prompt]
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AgentError.transport(String(describing: error))
        }

        guard let http = response as? HTTPURLResponse else {
            throw AgentError.invalidResponse("not HTTP")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AgentError.httpError(status: http.statusCode, body: body)
        }

        return try Self.decode(data: data, model: modelID)
    }

    // MARK: - Response decoding

    static func decode(data: Data, model: String) throws -> AgentResult {
        struct Envelope: Decodable {
            struct Block: Decodable {
                let type: String
                let text: String?
            }
            struct Usage: Decodable {
                let input_tokens: Int?
                let output_tokens: Int?
            }
            let content: [Block]
            let usage: Usage?
        }
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw AgentError.invalidResponse("decode failure: \(error)")
        }
        let text = envelope.content
            .filter { $0.type == "text" }
            .compactMap { $0.text }
            .joined()
        if text.isEmpty {
            throw AgentError.invalidResponse("empty assistant text")
        }
        return AgentResult(
            text: text,
            inputTokens: envelope.usage?.input_tokens ?? 0,
            outputTokens: envelope.usage?.output_tokens ?? 0,
            model: model
        )
    }
}
