import AuthenticationServices
import Foundation
import Observation
import CryptoKit

@Observable
@MainActor
final class AccountManager {
    static let shared = AccountManager()

    var currentUser: SyncAPIUser?
    var isAuthenticating: Bool = false
    var lastError: String?

    private let api: SyncAPI
    private var pendingAppleNonce: String?

    init(api: SyncAPI = SyncAPI(baseURL: SyncAPI.defaultBaseURL)) {
        self.api = api
    }

    var isSignedIn: Bool { currentUser != nil }

    func bootstrap() async {
        guard let token = KeychainStore.read(.sessionToken) else { return }
        do {
            currentUser = try await api.me(token: token)
        } catch let error as SyncAPIError where error.status == 401 {
            KeychainStore.delete(.sessionToken)
        } catch {
            // Leave the stored token in place on transient network failures;
            // `bootstrap` will retry next launch.
        }
    }

    func signUpEmail(email: String, password: String) async {
        await perform {
            let response = try await self.api.signUpEmail(email: email, password: password)
            try self.store(response)
        }
    }

    func signInEmail(email: String, password: String) async {
        await perform {
            let response = try await self.api.signInEmail(email: email, password: password)
            try self.store(response)
        }
    }

    // Called from AccountsSettingsView after SIWA completes with an
    // ASAuthorizationAppleIDCredential.
    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async {
        guard let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8),
              let nonce = pendingAppleNonce else {
            lastError = "Apple sign-in returned no identity token."
            return
        }
        defer { pendingAppleNonce = nil }

        await perform {
            let response = try await self.api.signInApple(
                identityToken: identityToken,
                nonce: nonce,
                email: credential.email,
                fullName: credential.fullName
            )
            try self.store(response)
        }
    }

    // Call this before presenting the SIWA request. Returns the SHA-256 hashed
    // nonce to set on ASAuthorizationAppleIDRequest.
    func prepareAppleRequest(on request: ASAuthorizationAppleIDRequest) {
        let raw = UUID().uuidString
        pendingAppleNonce = raw
        request.requestedScopes = [.email, .fullName]
        request.nonce = sha256(raw)
    }

    func signOut() async {
        guard let token = KeychainStore.read(.sessionToken) else {
            reset()
            return
        }
        try? await api.signOut(token: token)
        reset()
    }

    // MARK: - Private

    private func perform(_ block: @escaping () async throws -> Void) async {
        isAuthenticating = true
        lastError = nil
        defer { isAuthenticating = false }
        do {
            try await block()
        } catch let error as SyncAPIError {
            lastError = error.errorDescription ?? "Sign-in failed."
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func store(_ response: SignInResponse) throws {
        try KeychainStore.save(response.token, for: .sessionToken)
        currentUser = response.user
    }

    private func reset() {
        KeychainStore.delete(.sessionToken)
        currentUser = nil
    }

    private func sha256(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
