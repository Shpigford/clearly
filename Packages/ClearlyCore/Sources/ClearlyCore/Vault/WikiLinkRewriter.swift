import Foundation

/// In-place rewrite of `[[wiki-links]]` after a file is moved.
///
/// Given the source text of a note, the old target's vault-relative
/// path (with or without `.md` extension), and the new target's
/// vault-relative path, finds every link whose resolved target matches
/// the old path and rewrites it to the new path while preserving any
/// `#heading` anchor and `|alias` display text.
///
/// Matching is case-insensitive, mirroring `VaultIndex.resolveWikiLinkTargets`
/// — a link `[[Foo]]` resolves to `Foo.md`, `foo.md`, or `FOO.MD`. Both
/// path-style references (`[[notes/foo]]`) and bare-filename references
/// (`[[foo]]`) are recognized.
///
/// The rewritten target is the new vault-relative path with the markdown
/// extension stripped — `bar/baz` for a destination of `bar/baz.md`.
/// This is unambiguous across name collisions, at the cost of replacing
/// short-form references with longer path-form ones.
public enum WikiLinkRewriter {
    public struct Output: Equatable {
        public let newContent: String
        public let count: Int
    }

    public static func rewrite(content: String, oldTarget: String, newTarget: String) -> Output {
        let oldKey = canonicalKey(oldTarget)
        let oldBasename = stripMarkdownExtension(URL(fileURLWithPath: oldTarget).lastPathComponent).lowercased()
        let newRefTarget = stripMarkdownExtension(newTarget)

        let parse = FileParser.parse(content: content)
        let nsContent = content as NSString

        // Filter to matching links and sort descending by start so we
        // can splice without invalidating later ranges.
        var matches = parse.links.filter { link in
            let linkKey = canonicalKey(link.target)
            if linkKey == oldKey { return true }
            // Bare-filename references: `[[foo]]` matches old path
            // `notes/foo.md` because both have the same basename.
            let linkBasename = stripMarkdownExtension(URL(fileURLWithPath: link.target).lastPathComponent).lowercased()
            // Only match the basename when the link itself is bare —
            // otherwise `[[a/foo]]` could collide with a different
            // `b/foo.md` after a rename.
            return !link.target.contains("/") && linkBasename == oldBasename
        }
        matches.sort { $0.range.location > $1.range.location }

        var output = nsContent
        for match in matches {
            let replacement = renderLink(target: newRefTarget, heading: match.heading, alias: match.alias)
            output = output.replacingCharacters(in: match.range, with: replacement) as NSString
        }
        return Output(newContent: output as String, count: matches.count)
    }

    private static func canonicalKey(_ raw: String) -> String {
        stripMarkdownExtension(raw)
            .replacingOccurrences(of: "\\", with: "/")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripMarkdownExtension(_ raw: String) -> String {
        let url = URL(fileURLWithPath: raw)
        let ext = url.pathExtension.lowercased()
        if FileNode.markdownExtensions.contains(ext) {
            return url.deletingPathExtension().relativePath
        }
        return raw
    }

    private static func renderLink(target: String, heading: String?, alias: String?) -> String {
        var s = "[[\(target)"
        if let heading, !heading.isEmpty { s += "#\(heading)" }
        if let alias, !alias.isEmpty { s += "|\(alias)" }
        s += "]]"
        return s
    }
}
