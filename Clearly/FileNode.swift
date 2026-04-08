import Foundation

/// A node in the file tree representing a file or directory.
struct FileNode: Identifiable, Hashable {
    var id: URL { url }
    let name: String
    let url: URL
    var children: [FileNode]?

    var isDirectory: Bool { children != nil }

    static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdx", "txt"
    ]

    /// Build a file tree from a directory URL, filtering to markdown files.
    static func buildTree(at url: URL) -> [FileNode] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var folders: [FileNode] = []
        var files: [FileNode] = []

        for itemURL in contents {
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let name = itemURL.lastPathComponent

            if isDir {
                let children = buildTree(at: itemURL)
                // Only include folders that contain markdown files (directly or nested)
                if !children.isEmpty {
                    folders.append(FileNode(name: name, url: itemURL, children: children))
                }
            } else if markdownExtensions.contains(itemURL.pathExtension.lowercased()) {
                files.append(FileNode(name: name, url: itemURL, children: nil))
            }
        }

        folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return folders + files
    }
}
