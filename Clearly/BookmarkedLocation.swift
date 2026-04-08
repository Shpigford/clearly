import Foundation

/// A user-bookmarked folder location shown in the sidebar.
struct BookmarkedLocation: Identifiable {
    let id: UUID
    let url: URL
    var bookmarkData: Data
    var fileTree: [FileNode]
    var isAccessible: Bool

    init(id: UUID = UUID(), url: URL, bookmarkData: Data, fileTree: [FileNode] = [], isAccessible: Bool = false) {
        self.id = id
        self.url = url
        self.bookmarkData = bookmarkData
        self.fileTree = fileTree
        self.isAccessible = isAccessible
    }

    var name: String { url.lastPathComponent }
}

// MARK: - Persistence (Codable wrapper for UserDefaults)

struct StoredBookmark: Codable {
    let id: UUID
    let bookmarkData: Data
}
