import Foundation

/// A node in the file tree representing a file or directory.
struct FileNode: Identifiable, Hashable {
    var id: URL { url }
    let name: String
    let url: URL
    let isHidden: Bool
    var children: [FileNode]?

    var isDirectory: Bool { children != nil }

    static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdx", "txt"
    ]

    /// Build a file tree from a directory URL, filtering to markdown files.
    /// Skips hardcoded heavy directories and respects `.gitignore` rules.
    static func buildTree(at url: URL, showHiddenFiles: Bool = false, ignoreRules: IgnoreRules? = nil) -> [FileNode] {
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
                let children = FileNode.buildTree(at: itemURL, showHiddenFiles: showHiddenFiles, ignoreRules: childRules)
                // Only include folders that contain markdown files (directly or nested)
                if !children.isEmpty {
                    folders.append(FileNode(name: name, url: itemURL, isHidden: hidden, children: children))
                }
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

    static func buildTree(fromFileURLs fileURLs: [URL], rootURL: URL, showHiddenFiles: Bool = false) -> [FileNode] {
        let normalizedRootURL = rootURL.standardizedFileURL
        var ruleCache: [String: IgnoreRules] = [:]
        var directoryChildren: [String: [FileNode]] = [:]

        for fileURL in fileURLs {
            let normalizedFileURL = fileURL.standardizedFileURL
            guard markdownExtensions.contains(normalizedFileURL.pathExtension.lowercased()),
                  let relativeComponents = relativePathComponents(from: normalizedRootURL, to: normalizedFileURL),
                  !relativeComponents.isEmpty else {
                continue
            }

            if !showHiddenFiles, relativeComponents.contains(where: { $0.hasPrefix(".") }) {
                continue
            }

            guard !shouldIgnore(
                normalizedFileURL,
                from: normalizedRootURL,
                using: &ruleCache
            ) else {
                continue
            }

            insertNode(
                for: ArraySlice(relativeComponents),
                currentURL: normalizedRootURL,
                into: &directoryChildren
            )
        }

        return sortedNodes(in: normalizedRootURL, using: directoryChildren)
    }

    private static func insertNode(
        for components: ArraySlice<String>,
        currentURL: URL,
        into directoryChildren: inout [String: [FileNode]]
    ) {
        guard let component = components.first else { return }

        let itemURL = currentURL.appendingPathComponent(component, isDirectory: components.count > 1)
        let isHidden = component.hasPrefix(".")

        if components.count == 1 {
            let node = FileNode(name: component, url: itemURL, isHidden: isHidden, children: nil)
            append(node, to: currentURL, in: &directoryChildren)
            return
        }

        let folderNode = FileNode(name: component, url: itemURL, isHidden: isHidden, children: [])
        append(folderNode, to: currentURL, in: &directoryChildren)
        insertNode(for: components.dropFirst(), currentURL: itemURL, into: &directoryChildren)
    }

    private static func append(_ node: FileNode, to directoryURL: URL, in directoryChildren: inout [String: [FileNode]]) {
        let key = directoryURL.standardizedFileURL.path
        var children = directoryChildren[key] ?? []
        guard !children.contains(where: { $0.url == node.url }) else { return }
        children.append(node)
        directoryChildren[key] = children
    }

    private static func sortedNodes(in directoryURL: URL, using directoryChildren: [String: [FileNode]]) -> [FileNode] {
        let key = directoryURL.standardizedFileURL.path
        let children = directoryChildren[key] ?? []

        let resolvedChildren = children.map { node in
            guard node.isDirectory else { return node }
            return FileNode(
                name: node.name,
                url: node.url,
                isHidden: node.isHidden,
                children: sortedNodes(in: node.url, using: directoryChildren)
            )
        }

        let folders = resolvedChildren
            .filter(\.isDirectory)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let files = resolvedChildren
            .filter { !$0.isDirectory }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        return folders + files
    }

    private static func relativePathComponents(from rootURL: URL, to fileURL: URL) -> [String]? {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path

        guard filePath == rootPath || filePath.hasPrefix(rootPath + "/") else {
            return nil
        }

        let relativePath = filePath == rootPath
            ? ""
            : String(filePath.dropFirst(rootPath.count + 1))

        return relativePath
            .split(separator: "/")
            .map(String.init)
    }

    private static func shouldIgnore(_ fileURL: URL, from rootURL: URL, using cache: inout [String: IgnoreRules]) -> Bool {
        let normalizedRootURL = rootURL.standardizedFileURL
        guard let relativeComponents = relativePathComponents(from: normalizedRootURL, to: fileURL.standardizedFileURL) else {
            return false
        }

        var currentDirectoryURL = normalizedRootURL
        for component in relativeComponents.dropLast() {
            guard let rules = ignoreRules(forContentsOf: currentDirectoryURL, from: normalizedRootURL, using: &cache) else {
                return false
            }

            let childDirectoryURL = currentDirectoryURL.appendingPathComponent(component, isDirectory: true)
            if rules.shouldIgnore(url: childDirectoryURL, isDirectory: true) {
                return true
            }

            currentDirectoryURL = childDirectoryURL
        }

        guard let rules = ignoreRules(
            forContentsOf: fileURL.standardizedFileURL.deletingLastPathComponent(),
            from: normalizedRootURL,
            using: &cache
        ) else {
            return false
        }

        return rules.shouldIgnore(url: fileURL, isDirectory: false)
    }

    private static func ignoreRules(
        forContentsOf directoryURL: URL,
        from rootURL: URL,
        using cache: inout [String: IgnoreRules]
    ) -> IgnoreRules? {
        let normalizedRootURL = rootURL.standardizedFileURL
        let normalizedDirectoryURL = directoryURL.standardizedFileURL
        let cacheKey = normalizedDirectoryURL.path

        if let cachedRules = cache[cacheKey] {
            return cachedRules
        }

        guard isSameOrDescendant(normalizedDirectoryURL, of: normalizedRootURL) else {
            return nil
        }

        var rules = IgnoreRules(rootURL: normalizedRootURL)

        if normalizedDirectoryURL != normalizedRootURL,
           let relativeComponents = relativePathComponents(from: normalizedRootURL, to: normalizedDirectoryURL) {
            var currentURL = normalizedRootURL
            for component in relativeComponents {
                currentURL = currentURL.appendingPathComponent(component, isDirectory: true)
                rules.loadNestedGitignore(at: currentURL)
            }
        }

        cache[cacheKey] = rules
        return rules
    }

    private static func isSameOrDescendant(_ candidateURL: URL, of rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let candidatePath = candidateURL.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
}
