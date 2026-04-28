import Foundation

/// Picks user-dropped notes that haven't been linked from `index.md` yet so
/// the Integrate pass can hand them to the agent for indexing + cross-
/// referencing. Pure data — no I/O, no main-actor dependencies — so the
/// selection rules are unit-testable without filesystem fixtures.
public enum WikiIntegrationCandidates {

    /// Vault-relative `.md` paths that should be proposed for integration.
    /// Filters out wiki infrastructure (`raw/`, `_audit/`, `index.md`, etc.)
    /// and anything already referenced from `index.md` by either its full
    /// vault-relative stem or its basename stem. Returns results sorted so
    /// callers and tests see deterministic order.
    public static func select(allPaths: [String], indexContent: String) -> [String] {
        let indexed = indexedReferences(in: indexContent)
        let basenameCounts = allPaths.reduce(into: [String: Int]()) { counts, path in
            guard !WikiSystemFiles.isExcluded(vaultRelativePath: path) else { return }
            let withoutExt = path.hasSuffix(".md") ? String(path.dropLast(3)) : path
            let stem = (withoutExt as NSString).lastPathComponent.lowercased()
            counts[stem, default: 0] += 1
        }
        let unindexed = allPaths.filter { path in
            if WikiSystemFiles.isExcluded(vaultRelativePath: path) { return false }
            let withoutExt = path.hasSuffix(".md") ? String(path.dropLast(3)) : path
            let stem = (withoutExt as NSString).lastPathComponent
            let stemKey = stem.lowercased()
            let basenameIsUnique = basenameCounts[stemKey, default: 0] == 1
            return !indexed.contains(withoutExt.lowercased())
                && !(basenameIsUnique && indexed.contains(stemKey))
        }
        return unindexed.sorted()
    }

    /// Set of every `[[link]]` reference body found in `index.md`, normalised
    /// to lowercase with alias and section-anchor suffixes stripped — matching
    /// Obsidian's case-insensitive wiki-link semantics. Exposed for tests; the
    /// `select(allPaths:indexContent:)` entry point is the production caller.
    public static func indexedReferences(in indexContent: String) -> Set<String> {
        guard !indexContent.isEmpty else { return [] }
        let pattern = try! NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#)
        let ns = indexContent as NSString
        let range = NSRange(location: 0, length: ns.length)
        var refs: Set<String> = []
        for match in pattern.matches(in: indexContent, range: range) {
            let body = ns.substring(with: match.range(at: 1))
            var target = body
            if let pipe = target.firstIndex(of: "|") { target = String(target[..<pipe]) }
            if let hash = target.firstIndex(of: "#") { target = String(target[..<hash]) }
            target = target.trimmingCharacters(in: .whitespaces)
            if target.isEmpty { continue }
            refs.insert(target.lowercased())
        }
        return refs
    }
}
