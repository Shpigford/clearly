import Foundation

/// A user-bookmarked folder location shown in the sidebar.
public struct BookmarkedLocation: Identifiable {
    public let id: UUID
    public let url: URL
    public var bookmarkData: Data
    public var fileTree: [FileNode]
    public var isAccessible: Bool

    public init(id: UUID = UUID(), url: URL, bookmarkData: Data, fileTree: [FileNode] = [], isAccessible: Bool = false) {
        self.id = id
        self.url = url
        self.bookmarkData = bookmarkData
        self.fileTree = fileTree
        self.isAccessible = isAccessible
    }

    public var name: String { url.lastPathComponent }
}

// MARK: - Persistence (Codable wrapper for UserDefaults)

public struct StoredBookmark: Codable {
    public let id: UUID
    public let bookmarkData: Data

    public init(id: UUID, bookmarkData: Data) {
        self.id = id
        self.bookmarkData = bookmarkData
    }
}
