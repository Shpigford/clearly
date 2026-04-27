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

    /// Children for hierarchical UI rendering. Returns `nil` for both leaf files
    /// and empty folders so `OutlineGroup` / `DisclosureGroup` hides the
    /// disclosure indicator on items with nothing to expand.
    public var displayChildren: [FileNode]? {
        guard let children, !children.isEmpty else { return nil }
        return children
    }

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

    /// Build a disk-backed tree, then merge in watcher-provided files that may
    /// not be visible to `FileManager` yet, such as evicted iCloud placeholders.
    public static func buildTree(at url: URL, including files: [VaultFile], showHiddenFiles: Bool = false) -> [FileNode] {
        let rootURL = url.standardizedFileURL
        var tree = buildTree(at: rootURL, showHiddenFiles: showHiddenFiles)
        var existingFileURLs = fileURLs(in: tree)

        for file in files {
            let fileURL = file.url.standardizedFileURL
            guard isInside(fileURL, rootURL: rootURL) else { continue }
            guard !existingFileURLs.contains(fileURL) else { continue }
            guard markdownExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }

            insertFileNode(
                FileNode(
                    name: file.name,
                    url: file.url,
                    isHidden: file.name.hasPrefix("."),
                    children: nil
                ),
                into: &tree,
                rootURL: rootURL
            )
            existingFileURLs.insert(fileURL)
        }

        sortTree(&tree)
        return tree
    }

    private static func fileURLs(in nodes: [FileNode]) -> Set<URL> {
        var urls: Set<URL> = []
        func walk(_ node: FileNode) {
            if let children = node.children {
                children.forEach(walk)
            } else {
                urls.insert(node.url.standardizedFileURL)
            }
        }
        nodes.forEach(walk)
        return urls
    }

    private static func isInside(_ url: URL, rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(rootPath + "/")
    }

    private static func insertFileNode(_ fileNode: FileNode, into nodes: inout [FileNode], rootURL: URL) {
        let rootComponents = rootURL.standardizedFileURL.pathComponents
        let fileComponents = fileNode.url.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count else { return }

        let relativeComponents = Array(fileComponents.dropFirst(rootComponents.count))
        insertFileNode(fileNode, components: relativeComponents, currentURL: rootURL, nodes: &nodes)
    }

    private static func insertFileNode(_ fileNode: FileNode, components: [String], currentURL: URL, nodes: inout [FileNode]) {
        guard let head = components.first else { return }
        if components.count == 1 {
            if !nodes.contains(where: { $0.url.standardizedFileURL == fileNode.url.standardizedFileURL }) {
                nodes.append(fileNode)
            }
            return
        }

        let folderURL = currentURL.appendingPathComponent(head, isDirectory: true)
        let folderIndex: Int
        if let existing = nodes.firstIndex(where: { $0.url.standardizedFileURL == folderURL.standardizedFileURL }) {
            guard nodes[existing].isDirectory else { return }
            folderIndex = existing
        } else {
            nodes.append(FileNode(name: head, url: folderURL, isHidden: head.hasPrefix("."), children: []))
            folderIndex = nodes.index(before: nodes.endIndex)
        }

        var children = nodes[folderIndex].children ?? []
        insertFileNode(fileNode, components: Array(components.dropFirst()), currentURL: folderURL, nodes: &children)
        nodes[folderIndex].children = children
    }

    private static func sortTree(_ nodes: inout [FileNode]) {
        for index in nodes.indices {
            if var children = nodes[index].children {
                sortTree(&children)
                nodes[index].children = children
            }
        }
        nodes.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
