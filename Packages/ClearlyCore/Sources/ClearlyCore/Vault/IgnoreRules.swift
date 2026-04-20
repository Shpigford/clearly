import Foundation

/// Consolidates directory ignore logic: hardcoded skip list + .gitignore parsing.
/// Used by `FileNode.buildTree` and `VaultIndex.collectMarkdownFiles` to skip
/// heavy directories like node_modules and respect .gitignore rules.
public struct IgnoreRules {

    // MARK: - Hardcoded defaults

    /// Directories that are always skipped regardless of .gitignore.
    public static let defaultIgnoredDirectories: Set<String> = [
        // Version control
        ".git", ".svn", ".hg", "CVS",
        // Dependencies / packages
        "node_modules", "bower_components", "Pods", ".pub-cache", ".bundle",
        // Build output
        "build", "dist", ".build", ".next", ".nuxt", ".output", "out", "target", "_site",
        // Caches
        ".cache", ".parcel-cache", ".sass-cache",
        // Python
        "__pycache__", ".venv", "venv", ".tox",
        // Java / Gradle
        ".gradle",
        // IDE
        ".idea", ".vscode", ".vs", "xcuserdata",
        // Infrastructure
        ".terraform", ".vagrant", ".docker",
        // Test coverage
        "coverage", ".nyc_output",
        // Misc
        "vendor",
    ]

    // MARK: - Gitignore rules

    private struct Rule {
        let pattern: String
        let negated: Bool
        let directoryOnly: Bool
        /// Anchored rules match from the .gitignore's directory; unanchored match any path component.
        let anchored: Bool
        /// The directory containing the .gitignore that defined this rule.
        let basePath: URL
    }

    private var rules: [Rule] = []
    public let rootURL: URL

    // MARK: - Init

    public init(rootURL: URL) {
        self.rootURL = rootURL
        loadGitignore(at: rootURL)
    }

    // MARK: - Public API

    /// Returns `true` if the item at `url` should be skipped.
    public func shouldIgnore(url: URL, isDirectory: Bool) -> Bool {
        let name = url.lastPathComponent

        // Fast path: hardcoded directory names
        if isDirectory && Self.defaultIgnoredDirectories.contains(name) {
            return true
        }

        guard !rules.isEmpty else { return false }

        guard let relativePath = Self.relativePath(of: url, from: rootURL) else { return false }

        // Process rules in order — last match wins
        var ignored = false
        for rule in rules {
            if rule.directoryOnly && !isDirectory { continue }

            let pathToMatch: String
            if rule.basePath == rootURL {
                pathToMatch = relativePath
            } else {
                // Nested .gitignore: match relative to the .gitignore's directory
                guard let nestedRelative = Self.relativePath(of: url, from: rule.basePath) else { continue }
                pathToMatch = nestedRelative
            }

            if matches(pattern: rule.pattern, path: pathToMatch, anchored: rule.anchored) {
                ignored = !rule.negated
            }
        }
        return ignored
    }

    /// Load a nested .gitignore when entering a subdirectory.
    mutating func loadNestedGitignore(at directoryURL: URL) {
        loadGitignore(at: directoryURL)
    }

    // MARK: - Parsing

    private mutating func loadGitignore(at directoryURL: URL) {
        let gitignoreURL = directoryURL.appendingPathComponent(".gitignore")
        guard let contents = try? String(contentsOf: gitignoreURL, encoding: .utf8) else { return }

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingTrailingWhitespace()
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            var pattern = trimmed
            let negated = pattern.hasPrefix("!")
            if negated { pattern = String(pattern.dropFirst()) }

            let directoryOnly = pattern.hasSuffix("/")
            if directoryOnly { pattern = String(pattern.dropLast()) }

            // A pattern is anchored if it contains a slash anywhere (other than trailing, already stripped)
            // or starts with a slash. Leading slash is stripped after setting anchored.
            let anchored: Bool
            if pattern.hasPrefix("/") {
                anchored = true
                pattern = String(pattern.dropFirst())
            } else {
                anchored = pattern.contains("/")
            }

            guard !pattern.isEmpty else { continue }

            rules.append(Rule(
                pattern: pattern,
                negated: negated,
                directoryOnly: directoryOnly,
                anchored: anchored,
                basePath: directoryURL
            ))
        }
    }

    // MARK: - Matching

    /// Match a gitignore pattern against a relative path.
    private func matches(pattern: String, path: String, anchored: Bool) -> Bool {
        // Handle leading **/ — match anywhere in path
        if pattern.hasPrefix("**/") {
            let rest = String(pattern.dropFirst(3))
            // Try matching rest against full path and every suffix after a /
            if fnmatchWrap(rest, path) { return true }
            var idx = path.startIndex
            while let slashIdx = path[idx...].firstIndex(of: "/") {
                let after = path.index(after: slashIdx)
                if after < path.endIndex && fnmatchWrap(rest, String(path[after...])) {
                    return true
                }
                idx = after
            }
            return false
        }

        // Handle trailing /** — match everything under a directory
        if pattern.hasSuffix("/**") {
            let prefix = String(pattern.dropLast(3))
            return path == prefix || path.hasPrefix(prefix + "/")
        }

        // Handle infix /**/ — zero-or-more intermediate directories
        if pattern.contains("/**/") {
            let parts = pattern.components(separatedBy: "/**/")
            if parts.count == 2 {
                let left = parts[0]
                let right = parts[1]
                // Must start with left, end matching right, with anything in between
                guard fnmatchWrap(left, path) || path.hasPrefix(left + "/") else { return false }
                // Try matching right against every suffix
                if fnmatchWrap(left + "/" + right, path) { return true }
                var idx = path.startIndex
                while let slashIdx = path[idx...].firstIndex(of: "/") {
                    let after = path.index(after: slashIdx)
                    if after < path.endIndex && fnmatchWrap(right, String(path[after...])) {
                        return true
                    }
                    idx = after
                }
            }
            return false
        }

        if anchored {
            return fnmatchWrap(pattern, path)
        } else {
            // Unanchored: match against just the last component
            let filename = (path as NSString).lastPathComponent
            return fnmatchWrap(pattern, filename)
        }
    }

    /// Wrapper around POSIX fnmatch with FNM_PATHNAME.
    private func fnmatchWrap(_ pattern: String, _ string: String) -> Bool {
        Darwin.fnmatch(pattern, string, FNM_PATHNAME) == 0
    }

    // MARK: - Helpers

    private static func relativePath(of url: URL, from base: URL) -> String? {
        let filePath = url.standardizedFileURL.path
        let basePath = base.standardizedFileURL.path
        if filePath == basePath { return "" }
        guard filePath.hasPrefix(basePath + "/") else { return nil }
        return String(filePath.dropFirst(basePath.count + 1))
    }
}

// MARK: - String helpers

private extension String {
    public func trimmingTrailingWhitespace() -> String {
        var s = self
        while let last = s.last, last == " " || last == "\t" {
            s.removeLast()
        }
        return s
    }
}
