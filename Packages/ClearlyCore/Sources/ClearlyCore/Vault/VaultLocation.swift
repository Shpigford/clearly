import Foundation

public struct VaultLocation: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case defaultICloud
        case pickedICloud
        case local
    }

    public let id: UUID
    public let kind: Kind
    public let url: URL
    public let bookmarkData: Data?

    public init(id: UUID = UUID(), kind: Kind, url: URL, bookmarkData: Data? = nil) {
        self.id = id
        self.kind = kind
        self.url = url
        self.bookmarkData = bookmarkData
    }

    public var displayName: String {
        switch kind {
        case .defaultICloud: return "iCloud Drive / Clearly"
        case .pickedICloud, .local: return url.lastPathComponent
        }
    }
}

public struct StoredVaultLocation: Codable, Sendable {
    public let id: UUID
    public let kind: VaultLocation.Kind
    public let bookmarkData: Data?

    public init(id: UUID, kind: VaultLocation.Kind, bookmarkData: Data?) {
        self.id = id
        self.kind = kind
        self.bookmarkData = bookmarkData
    }

    public init(_ location: VaultLocation) {
        self.id = location.id
        self.kind = location.kind
        self.bookmarkData = location.bookmarkData
    }
}

public enum VaultLocationError: Error, Sendable {
    case iCloudUnavailable
    case bookmarkInvalidated
    case bookmarkResolutionFailed(underlying: Error?)
    case securityScopeDenied
}

extension VaultLocation {
    /// Resolve a previously persisted location back into a live `VaultLocation`.
    ///
    /// - `.defaultICloud`: re-resolved via `CloudVault.ubiquityContainerURL()` each launch; no bookmark.
    /// - `.pickedICloud` / `.local`: resolved from security-scoped bookmark; `startAccessingSecurityScopedResource`
    ///   is called on the returned URL so callers can use it directly. Callers are responsible for
    ///   `stopAccessingSecurityScopedResource()` when replacing the vault.
    public static func resolve(from stored: StoredVaultLocation) async throws -> VaultLocation {
        switch stored.kind {
        case .defaultICloud:
            guard let url = await CloudVault.ubiquityContainerURL() else {
                throw VaultLocationError.iCloudUnavailable
            }
            return VaultLocation(id: stored.id, kind: .defaultICloud, url: url, bookmarkData: nil)

        case .pickedICloud, .local:
            guard let bookmarkData = stored.bookmarkData else {
                throw VaultLocationError.bookmarkInvalidated
            }
            var isStale = false
            let url: URL
            do {
                #if os(iOS)
                url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                #else
                url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                #endif
            } catch {
                throw VaultLocationError.bookmarkResolutionFailed(underlying: error)
            }
            if isStale {
                throw VaultLocationError.bookmarkInvalidated
            }
            guard url.startAccessingSecurityScopedResource() else {
                throw VaultLocationError.securityScopeDenied
            }
            return VaultLocation(id: stored.id, kind: stored.kind, url: url, bookmarkData: bookmarkData)
        }
    }
}
