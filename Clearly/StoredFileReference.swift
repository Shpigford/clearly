import Foundation

struct StoredFileReference: Codable {
    let requiresSecurityScopedAccess: Bool
    let bookmarkData: Data?
    let url: URL?

    init(requiresSecurityScopedAccess: Bool, bookmarkData: Data?, url: URL?) {
        self.requiresSecurityScopedAccess = requiresSecurityScopedAccess
        self.bookmarkData = bookmarkData
        self.url = url
    }

    init(url: URL, requiresSecurityScopedAccess: Bool) {
        self.requiresSecurityScopedAccess = requiresSecurityScopedAccess

        if requiresSecurityScopedAccess {
            bookmarkData = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            self.url = nil
        } else {
            bookmarkData = nil
            self.url = url.standardizedFileURL
        }
    }
}
