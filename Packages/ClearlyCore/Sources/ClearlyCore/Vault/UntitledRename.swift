import Foundation

/// Notes.app-style auto-rename helpers for `untitled.md` vault files. Pure
/// logic kept out of `VaultSession` (iOS-only) so Mac's `WorkspaceManager`
/// can derive identical rename targets on save.
public enum UntitledRename {
    /// Matches `untitled`, `untitled-2`, `untitled 2`, `Untitled`, `Untitled 2`, …
    /// Case-insensitive, accepts space and dash separators so legacy
    /// title-case files still trigger auto-rename after the kebab pivot.
    public static func isUntitledStem(_ stem: String) -> Bool {
        return stem.range(of: #"^untitled([\s-]\d+)?$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Destination URL for an auto-rename if `url` is currently named
    /// `untitled*`, `text` yields a non-empty sanitized first heading/line,
    /// and a collision-free slot (`stem.ext` or `stem N.ext`) exists in the
    /// same parent directory. `nil` otherwise. Casing and spaces from the
    /// source text are preserved — only filesystem-invalid chars are stripped.
    public static func proposedRenameURL(for url: URL, text: String) -> URL? {
        let stem = (url.lastPathComponent as NSString).deletingPathExtension
        guard isUntitledStem(stem) else { return nil }
        guard let rawTitle = extractTitle(from: text) else { return nil }
        let sanitized = sanitizeFilename(rawTitle)
        guard !sanitized.isEmpty, sanitized != stem else { return nil }

        let parent = url.deletingLastPathComponent()
        let ext = url.pathExtension.isEmpty ? "md" : url.pathExtension

        var candidate = sanitized
        var attempt = 1
        while FileManager.default.fileExists(atPath: parent.appendingPathComponent("\(candidate).\(ext)").path) {
            attempt += 1
            candidate = "\(sanitized) \(attempt)"
            if attempt > 50 { return nil }
        }
        return parent.appendingPathComponent("\(candidate).\(ext)")
    }

    /// Next available `untitled.md` / `untitled 2.md` / … URL inside `parent`.
    public static func nextUntitledURL(in parent: URL, extension ext: String = "md") -> URL {
        var attempt = 0
        var url: URL
        repeat {
            attempt += 1
            let name = attempt == 1 ? "untitled.\(ext)" : "untitled \(attempt).\(ext)"
            url = parent.appendingPathComponent(name)
        } while FileManager.default.fileExists(atPath: url.path)
        return url
    }

    /// Lightly sanitize a filename stem: strip `/`, `\`, `:`, `?`, `*`, `"`,
    /// `<`, `>`, `|`, NUL, and control characters; trim surrounding
    /// whitespace; drop any leading dot so the file isn't hidden; cap at
    /// 240 characters so there's room for the extension and a collision
    /// suffix under APFS's 255-byte filename limit. Casing and internal
    /// spaces are preserved exactly as typed.
    public static func sanitizeFilename(_ raw: String) -> String {
        let forbidden: Set<Character> = ["/", "\\", ":", "?", "*", "\"", "<", ">", "|"]
        var result = ""
        for char in raw {
            if forbidden.contains(char) { continue }
            if char.unicodeScalars.contains(where: { $0.value == 0 || $0.properties.generalCategory == .control }) {
                continue
            }
            result.append(char)
        }
        var trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix(".") { trimmed.removeFirst() }
        if trimmed.count > 240 { trimmed = String(trimmed.prefix(240)) }
        return trimmed
    }

    static func extractTitle(from text: String) -> String? {
        let stripped = stripLeadingFrontmatter(text)
        for raw in stripped.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.hasPrefix("#") {
                let withoutHashes = String(trimmed.drop(while: { $0 == "#" }))
                let cleaned = withoutHashes.trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? nil : cleaned
            }
            return trimmed
        }
        return nil
    }

    static func stripLeadingFrontmatter(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return text }
        var endIdx: Int?
        for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" {
            endIdx = i
            break
        }
        guard let endIdx else { return text }
        return lines[(endIdx + 1)...].joined(separator: "\n")
    }
}
