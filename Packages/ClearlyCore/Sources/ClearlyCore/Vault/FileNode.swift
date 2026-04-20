import Foundation

/// A node in the file tree representing a file or directory.
public struct FileNode: Identifiable, Hashable {
    public var id: URL { url }
    public let name: String
    public let url: URL
    public let isHidden: Bool
    public var children: [FileNode]?

    public init(name: String, url: URL, isHidden: Bool, children: [FileNode]? = nil) {
        self.name = name
        self.url = url
        self.isHidden = isHidden
        self.children = children
    }

    public var isDirectory: Bool { children != nil }

    public static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdx", "txt"
    ]

    /// Build a file tree from a directory URL, filtering to markdown files.
    /// Skips hardcoded heavy directories and respects `.gitignore` rules.
    public static func buildTree(at url: URL, showHiddenFiles: Bool = false, ignoreRules: IgnoreRules? = nil) -> [FileNode] {
        let fm = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: options
        ) else { return [] }

        var rules = ignoreRules ?? IgnoreRules(rootURL: url)

        var folders: [FileNode] = []
        var files: [FileNode] = []

        for itemURL in contents {
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let name = itemURL.lastPathComponent
            let hidden = name.hasPrefix(".")

            if isDir {
                if rules.shouldIgnore(url: itemURL, isDirectory: true) { continue }
                var childRules = rules
                childRules.loadNestedGitignore(at: itemURL)
                let children = buildTree(at: itemURL, showHiddenFiles: showHiddenFiles, ignoreRules: childRules)
                folders.append(FileNode(name: name, url: itemURL, isHidden: hidden, children: children))
            } else {
                if rules.shouldIgnore(url: itemURL, isDirectory: false) { continue }
                if markdownExtensions.contains(itemURL.pathExtension.lowercased()) {
                    files.append(FileNode(name: name, url: itemURL, isHidden: hidden, children: nil))
                }
            }
        }

        folders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        files.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return folders + files
    }
}
