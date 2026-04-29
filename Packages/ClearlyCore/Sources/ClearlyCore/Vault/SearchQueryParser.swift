import Foundation

/// A parsed search query: free-text terms plus optional structured filters.
///
/// The CLI/MCP search surface accepts query strings like
/// `"tag:work tag:urgent path:journal/ retro"`. Operators are split out
/// here so the SQL layer can JOIN against the `tags` table and filter
/// `files.path` without changing the FTS5 schema.
public struct ParsedSearchQuery: Equatable, Sendable {
    /// Free-text portion of the query, ready for FTS5 MATCH. May be empty
    /// when the user specified only filters (e.g. `tag:work`); callers
    /// should treat that as "match every file that satisfies the
    /// filters".
    public let ftsQuery: String

    /// Tags the file must carry (case-insensitive, AND-combined). Empty
    /// when no `tag:` operator was used.
    public let tagFilters: [String]

    /// Vault-relative path prefix (case-insensitive) the file must start
    /// with. Nil when no `path:` operator was used. Only the first
    /// `path:` operator wins — additional ones are ignored.
    public let pathPrefix: String?

    public init(ftsQuery: String, tagFilters: [String], pathPrefix: String?) {
        self.ftsQuery = ftsQuery
        self.tagFilters = tagFilters
        self.pathPrefix = pathPrefix
    }

    public var hasFilters: Bool {
        !tagFilters.isEmpty || pathPrefix != nil
    }
}

public enum SearchQueryParser {
    /// Pulls `tag:<value>` and `path:<value>` operators out of a query
    /// string, leaving everything else for FTS5. Quoted phrases pass
    /// through to FTS unchanged.
    ///
    /// Recognized operators:
    /// - `tag:foo` — file must carry the tag (case-insensitive). Repeat
    ///   to AND multiple tags. The value cannot contain spaces; use
    ///   underscores or hyphens, matching how tags are stored.
    /// - `path:notes/sub` — file's vault-relative path must start with
    ///   this prefix (case-insensitive). Only the first `path:` wins.
    ///
    /// Unknown operators (e.g. `foo:bar`) pass through to FTS verbatim
    /// so we don't surprise users searching for literal `key:value`
    /// substrings.
    public static func parse(_ raw: String) -> ParsedSearchQuery {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return ParsedSearchQuery(ftsQuery: "", tagFilters: [], pathPrefix: nil)
        }

        var ftsTokens: [String] = []
        var tagFilters: [String] = []
        var pathPrefix: String?

        for token in tokenize(trimmed) {
            if token.hasPrefix("\"") {
                // Quoted phrase — pass through verbatim.
                ftsTokens.append(token)
                continue
            }
            if let (op, value) = splitOperator(token), !value.isEmpty {
                switch op {
                case "tag":
                    tagFilters.append(value.lowercased())
                    continue
                case "path":
                    if pathPrefix == nil {
                        pathPrefix = value
                    }
                    continue
                default:
                    // Unknown operator — fall through as a literal term.
                    break
                }
            }
            ftsTokens.append(token)
        }

        return ParsedSearchQuery(
            ftsQuery: ftsTokens.joined(separator: " "),
            tagFilters: tagFilters,
            pathPrefix: pathPrefix
        )
    }

    /// Split a string into whitespace-separated tokens, preserving
    /// quoted phrases as single tokens (with their quotes intact).
    private static func tokenize(_ input: String) -> [String] {
        var tokens: [String] = []
        var buffer = ""
        var inQuotes = false
        for ch in input {
            if ch == "\"" {
                buffer.append(ch)
                inQuotes.toggle()
                continue
            }
            if ch.isWhitespace, !inQuotes {
                if !buffer.isEmpty {
                    tokens.append(buffer)
                    buffer = ""
                }
                continue
            }
            buffer.append(ch)
        }
        if !buffer.isEmpty {
            tokens.append(buffer)
        }
        return tokens
    }

    private static func splitOperator(_ token: String) -> (op: String, value: String)? {
        guard let colonIdx = token.firstIndex(of: ":") else { return nil }
        let op = String(token[token.startIndex..<colonIdx]).lowercased()
        let value = String(token[token.index(after: colonIdx)...])
        guard !op.isEmpty else { return nil }
        return (op, value)
    }
}
