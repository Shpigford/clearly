import Foundation
import Security

/// Thin Security.framework wrapper for storing API keys. The service name is
/// the Keychain "service" attribute; all items under the same service show up
/// together in Keychain Access, which makes manual inspection easy.
/// Cross-platform via Foundation + Security — reusable by iOS once BYOK lands
/// there.
public struct KeychainStore: Sendable {
    public static let service = "com.sabotage.clearly.wiki"

    public enum KeychainError: Error, Equatable, Sendable {
        case unhandledStatus(OSStatus)
        case invalidUTF8
    }

    public let service: String

    public init(service: String = KeychainStore.service) {
        self.service = service
    }

    // MARK: - API

    public func set(_ value: String, forKey account: String) throws {
        guard let data = value.data(using: .utf8) else { throw KeychainError.invalidUTF8 }
        try removeQuietly(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    public func get(_ account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let text = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidUTF8
            }
            return text
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    public func remove(_ account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    public func hasValue(_ account: String) -> Bool {
        (try? get(account)) != nil
    }

    // MARK: - Private

    private func removeQuietly(account: String) throws {
        try? remove(account)
    }
}

/// Canonical account names used by the Wiki subsystem.
public enum WikiKeychainAccount {
    public static let anthropicAPIKey = "anthropic.api_key"
    public static let openAIAPIKey = "openai.api_key"
    public static let openAICompatibleAPIKey = "openai_compatible.api_key"
}
