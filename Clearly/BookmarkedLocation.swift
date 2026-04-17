import Foundation

enum VaultLocationKind: String, Codable {
    case localBookmark
    case iCloud
}

/// A user-bookmarked folder location shown in the sidebar.
struct BookmarkedLocation: Identifiable {
    let id: UUID
    let url: URL
    var kind: VaultLocationKind
    var bookmarkData: Data?
    var fileTree: [FileNode]
    var isAccessible: Bool

    init(
        id: UUID = UUID(),
        url: URL,
        kind: VaultLocationKind = .localBookmark,
        bookmarkData: Data? = nil,
        fileTree: [FileNode] = [],
        isAccessible: Bool = false
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.bookmarkData = bookmarkData
        self.fileTree = fileTree
        self.isAccessible = isAccessible
    }

    var name: String { url.lastPathComponent }

    var requiresSecurityScopedAccess: Bool {
        kind == .localBookmark
    }
}

// MARK: - Persistence (Codable wrapper for UserDefaults)

struct StoredLocation: Codable {
    let id: UUID
    let kind: VaultLocationKind
    let bookmarkData: Data?
    let url: URL?

    init(id: UUID, kind: VaultLocationKind, bookmarkData: Data?, url: URL?) {
        self.id = id
        self.kind = kind
        self.bookmarkData = bookmarkData
        self.url = url
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case bookmarkData
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)

        if let kind = try container.decodeIfPresent(VaultLocationKind.self, forKey: .kind) {
            self.kind = kind
            bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
            url = try container.decodeIfPresent(URL.self, forKey: .url)
            return
        }

        self.kind = .localBookmark
        bookmarkData = try container.decode(Data.self, forKey: .bookmarkData)
        url = nil
    }
}
