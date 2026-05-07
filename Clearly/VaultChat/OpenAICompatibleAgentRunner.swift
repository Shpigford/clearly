import Foundation
import ClearlyCore

/// Calls an OpenAI-compatible Chat Completions API. This covers OpenAI's
/// hosted API and local servers such as LM Studio that expose `/v1` endpoints.
struct OpenAICompatibleAgentRunner: AgentRunner {
    let settings: Settings
    let urlSession: URLSession

    init(settings: Settings, urlSession: URLSession = .shared) {
        self.settings = settings
        self.urlSession = urlSession
    }

    func run(prompt: String, model: String?) async throws -> AgentResult {
        let selectedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? settings.model
        let requestBody = ChatCompletionRequest(
            model: selectedModel,
            messages: [.init(role: "user", content: prompt)],
            reasoning_effort: settings.thinkingLevel.requestValue
        )
        var request = URLRequest(url: Self.chatCompletionsEndpoint(for: settings.baseURL))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        applyAuthorization(to: &request)
        request.httpBody = try JSONEncoder().encode(requestBody)

        do {
            let (data, response) = try await urlSession.data(for: request)
            try Self.validateHTTPResponse(response, data: data)
            return try Self.decodeChatCompletion(data: data, fallbackModel: selectedModel)
        } catch let error as AgentError {
            throw error
        } catch {
            throw AgentError.transport(error.localizedDescription)
        }
    }

    private func applyAuthorization(to request: inout URLRequest) {
        let token = settings.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    // MARK: - Settings

    struct Settings: Sendable, Equatable {
        static let defaultBaseURLString = "https://api.openai.com/v1"

        let baseURL: URL
        let token: String
        let model: String
        let thinkingLevel: ThinkingLevel

        static func loadFromUserDefaults(_ defaults: UserDefaults = .standard) throws -> Settings {
            let baseURLString = defaults.string(forKey: Keys.baseURL) ?? defaultBaseURLString
            let baseURL = try normalizedBaseURL(from: baseURLString)
            let model = (defaults.string(forKey: Keys.model) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else {
                throw VaultChatAPIConfigurationError.missingModel
            }
            let thinkingRaw = defaults.string(forKey: Keys.thinkingLevel) ?? ThinkingLevel.providerDefault.rawValue
            let thinkingLevel = ThinkingLevel(rawValue: thinkingRaw) ?? .providerDefault
            let token = try ChatAPIKeychain.loadToken() ?? ""
            return Settings(
                baseURL: baseURL,
                token: token,
                model: model,
                thinkingLevel: thinkingLevel
            )
        }

        static func normalizedBaseURL(from rawValue: String) throws -> URL {
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw VaultChatAPIConfigurationError.invalidBaseURL(rawValue)
            }

            let candidate: String
            if trimmed.contains("://") {
                candidate = trimmed
            } else if trimmed.hasPrefix("localhost") ||
                        trimmed.hasPrefix("127.0.0.1") ||
                        trimmed.hasPrefix("0.0.0.0") {
                candidate = "http://\(trimmed)"
            } else {
                candidate = "https://\(trimmed)"
            }

            guard let url = URL(string: candidate),
                  let scheme = url.scheme?.lowercased(),
                  (scheme == "http" || scheme == "https"),
                  url.host != nil
            else {
                throw VaultChatAPIConfigurationError.invalidBaseURL(rawValue)
            }
            return url
        }
    }

    enum Keys {
        static let defaultBackend = "cli"
        static let backend = "vaultChatBackend"
        static let baseURL = "vaultChatAPIBaseURL"
        static let model = "vaultChatAPIModel"
        static let thinkingLevel = "vaultChatAPIThinkingLevel"
    }

    enum ThinkingLevel: String, CaseIterable, Identifiable, Sendable {
        case providerDefault = "default"
        case minimal
        case low
        case medium
        case high

        var id: String { rawValue }

        var label: String {
            switch self {
            case .providerDefault: return "Provider default"
            case .minimal: return "Minimal"
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            }
        }

        var requestValue: String? {
            self == .providerDefault ? nil : rawValue
        }
    }

    // MARK: - Model listing

    static func fetchModels(baseURLString: String, token: String) async throws -> [String] {
        let baseURL = try Settings.normalizedBaseURL(from: baseURLString)
        var request = URLRequest(url: modelsEndpoint(for: baseURL))
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty {
            request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validateHTTPResponse(response, data: data)
            let decoded = try JSONDecoder().decode(ModelListResponse.self, from: data)
            return Array(Set(decoded.data.map(\.id)))
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        } catch let error as AgentError {
            throw error
        } catch {
            throw AgentError.transport(error.localizedDescription)
        }
    }

    // MARK: - Endpoint normalization

    private enum Endpoint {
        case chatCompletions
        case models
    }

    private static func chatCompletionsEndpoint(for baseURL: URL) -> URL {
        endpointURL(for: baseURL, endpoint: .chatCompletions)
    }

    private static func modelsEndpoint(for baseURL: URL) -> URL {
        endpointURL(for: baseURL, endpoint: .models)
    }

    private static func endpointURL(for baseURL: URL, endpoint: Endpoint) -> URL {
        var url = strippedEndpointURL(baseURL)
        if pathComponents(url).isEmpty {
            url.appendPathComponent("v1")
        }
        switch endpoint {
        case .chatCompletions:
            url.appendPathComponent("chat")
            url.appendPathComponent("completions")
        case .models:
            url.appendPathComponent("models")
        }
        return url
    }

    private static func strippedEndpointURL(_ url: URL) -> URL {
        var base = url
        let components = pathComponents(base)
        if components.suffix(2) == ["chat", "completions"] {
            base.deleteLastPathComponent()
            base.deleteLastPathComponent()
        } else if components.last == "models" {
            base.deleteLastPathComponent()
        }
        return base
    }

    private static func pathComponents(_ url: URL) -> [String] {
        url.pathComponents.filter { $0 != "/" }
    }

    // MARK: - Request / response

    private struct ChatCompletionRequest: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }

        let model: String
        let messages: [Message]
        let reasoning_effort: String?
    }

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: MessageContent?
            }

            let message: Message?
        }

        struct Usage: Decodable {
            let prompt_tokens: Int?
            let completion_tokens: Int?
        }

        let choices: [Choice]
        let usage: Usage?
        let model: String?
    }

    private enum MessageContent: Decodable {
        struct Part: Decodable {
            let text: String?
        }

        case string(String)
        case parts([Part])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .string(string)
                return
            }
            if let parts = try? container.decode([Part].self) {
                self = .parts(parts)
                return
            }
            throw DecodingError.typeMismatch(
                MessageContent.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected string or text parts for message content"
                )
            )
        }

        var text: String {
            switch self {
            case .string(let value):
                return value
            case .parts(let parts):
                return parts.compactMap(\.text).joined()
            }
        }
    }

    private struct ModelListResponse: Decodable {
        struct Model: Decodable {
            let id: String
        }

        let data: [Model]
    }

    private struct APIErrorResponse: Decodable {
        struct APIError: Decodable {
            let message: String?
        }

        let error: APIError?
    }

    private static func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AgentError.invalidResponse("API returned a non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
            let apiMessage = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))
                .flatMap { $0.error?.message }
            throw AgentError.httpError(
                status: http.statusCode,
                body: String((apiMessage ?? body).prefix(512))
            )
        }
    }

    private static func decodeChatCompletion(data: Data, fallbackModel: String) throws -> AgentResult {
        let response: ChatCompletionResponse
        do {
            response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw AgentError.invalidResponse("API JSON decode failure: \(error); raw: \(raw.prefix(512))")
        }

        let text = response.choices
            .compactMap { $0.message?.content?.text }
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else {
            throw AgentError.invalidResponse("API returned an empty assistant message")
        }

        return AgentResult(
            text: text,
            inputTokens: response.usage?.prompt_tokens ?? 0,
            outputTokens: response.usage?.completion_tokens ?? 0,
            model: response.model ?? fallbackModel
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

enum VaultChatAPIConfigurationError: LocalizedError, Equatable {
    case invalidBaseURL(String)
    case missingModel

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Enter a valid API base URL in Settings > Chat."
        case .missingModel:
            return "Choose an API model in Settings > Chat."
        }
    }
}
