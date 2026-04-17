import Foundation

struct SyncAPIUser: Codable, Equatable {
    let id: String
    let emailAddress: String?
    let subscriptionStatus: String

    enum CodingKeys: String, CodingKey {
        case id
        case emailAddress = "email_address"
        case subscriptionStatus = "subscription_status"
    }
}

struct SignInResponse: Codable {
    let token: String
    let user: SyncAPIUser
}

struct SyncAPIError: Error, LocalizedError {
    let status: Int
    let code: String?
    let message: String?

    var errorDescription: String? {
        if let message { return message }
        if let code { return "\(code) (HTTP \(status))" }
        return "HTTP \(status)"
    }
}

struct SyncAPI {
    let baseURL: URL
    var session: URLSession = .shared

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    static var defaultBaseURL: URL {
        if let override = Bundle.main.object(forInfoDictionaryKey: "SyncAPIURL") as? String,
           let url = URL(string: override) {
            return url
        }
        return URL(string: "http://localhost:3000")!
    }

    // MARK: - Auth

    func signUpEmail(email: String, password: String) async throws -> SignInResponse {
        try await post("/auth/users", body: [
            "user": ["email_address": email, "password": password]
        ])
    }

    func signInEmail(email: String, password: String) async throws -> SignInResponse {
        try await post("/auth/sessions", body: [
            "session": ["email_address": email, "password": password]
        ])
    }

    func signInApple(identityToken: String, nonce: String, email: String?, fullName: PersonNameComponents?) async throws -> SignInResponse {
        var body: [String: Any] = [
            "identity_token": identityToken,
            "nonce": nonce,
        ]
        if let email { body["email"] = email }
        if let fullName { body["full_name"] = PersonNameComponentsFormatter().string(from: fullName) }
        return try await post("/auth/apple", body: body)
    }

    func me(token: String) async throws -> SyncAPIUser {
        try await get("/api/v1/me", token: token)
    }

    func signOut(token: String) async throws {
        _ = try await requestEmpty("DELETE", path: "/auth/sessions/current", token: token)
    }

    // MARK: - Transport

    private func post<T: Decodable>(_ path: String, body: [String: Any], token: String? = nil) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: body)
        let (respData, _) = try await request("POST", path: path, body: data, token: token)
        return try decode(respData)
    }

    private func get<T: Decodable>(_ path: String, token: String?) async throws -> T {
        let (data, _) = try await request("GET", path: path, body: nil, token: token)
        return try decode(data)
    }

    @discardableResult
    private func requestEmpty(_ method: String, path: String, token: String?) async throws -> HTTPURLResponse {
        let (_, response) = try await request(method, path: path, body: nil, token: token)
        return response
    }

    private func request(_ method: String, path: String, body: Data?, token: String?) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { req.httpBody = body }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if !(200..<300).contains(http.statusCode) {
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
            throw SyncAPIError(status: http.statusCode, code: decoded?["error"], message: decoded?["detail"])
        }
        return (data, http)
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    }
}
