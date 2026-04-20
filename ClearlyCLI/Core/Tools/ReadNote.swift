import Foundation
import ClearlyCore
import CryptoKit

struct ReadNoteArgs: Codable {
    let relativePath: String
    let startLine: Int?
    let endLine: Int?
    let vault: String?
}

struct ReadNoteResult: Codable {
    struct HeadingEntry: Codable {
        let text: String
        let level: Int
        let lineNumber: Int
    }
    struct LineRange: Codable {
        let start: Int
        let end: Int
    }

    let vault: String
    let relativePath: String
    let content: String
    let contentHash: String
    let sizeBytes: Int
    let modifiedAt: String
    /// Flattened from FrontmatterSupport.Block.fields. Duplicate keys resolve
    /// last-write-wins — same convention FileParser uses when reading a single
    /// logical value per key.
    let frontmatter: [String: String]
    let headings: [HeadingEntry]
    let tags: [String]
    let lineRange: LineRange?
}

func readNote(_ args: ReadNoteArgs, vaults: [LoadedVault]) async throws -> ReadNoteResult {
    guard !args.relativePath.isEmpty else {
        throw ToolError.missingArgument("relative_path")
    }

    switch try VaultResolver.resolve(relativePath: args.relativePath, hint: args.vault, in: vaults) {
    case .notFound:
        throw ToolError.noteNotFound(args.relativePath)
    case .ambiguous(let matches):
        throw ToolError.ambiguousVault(
            relativePath: args.relativePath,
            matches: matches.map { $0.url.lastPathComponent }
        )
    case .resolved(let loaded):
        let fileURL = try PathGuard.resolve(relativePath: args.relativePath, in: loaded.url)
        let rawData: Data
        do {
            rawData = try Data(contentsOf: fileURL)
        } catch {
            // VaultResolver confirmed the file exists, so a read failure here
            // is either a TOCTOU race (file was deleted between check and
            // read) or a permission denial. noteNotFound is the closest stable
            // identifier for both; Phase 3 may split out an io_error surface.
            throw ToolError.noteNotFound(args.relativePath)
        }
        guard let fullContent = String(data: rawData, encoding: .utf8) else {
            throw ToolError.invalidEncoding(args.relativePath)
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let modifiedAt = (attrs?[.modificationDate] as? Date) ?? Date()
        let sizeBytes = rawData.count

        let hash = SHA256.hash(data: rawData)
        let contentHash = hash.map { String(format: "%02x", $0) }.joined()

        let (slice, lineRange) = applyLineRange(
            fullContent,
            start: args.startLine,
            end: args.endLine
        )

        let frontmatter: [String: String]
        if let block = FrontmatterSupport.extract(from: fullContent) {
            var dict: [String: String] = [:]
            for field in block.fields {
                dict[field.key] = field.value
            }
            frontmatter = dict
        } else {
            frontmatter = [:]
        }

        let indexed = loaded.index.file(forRelativePath: args.relativePath)
        let headings: [ReadNoteResult.HeadingEntry]
        let tags: [String]
        if let indexed {
            headings = loaded.index.headings(forFileId: indexed.id).map {
                ReadNoteResult.HeadingEntry(text: $0.text, level: $0.level, lineNumber: $0.lineNumber)
            }
            tags = loaded.index.tags(forFileId: indexed.id)
        } else {
            headings = []
            tags = []
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return ReadNoteResult(
            vault: loaded.url.lastPathComponent,
            relativePath: args.relativePath,
            content: slice,
            contentHash: contentHash,
            sizeBytes: sizeBytes,
            modifiedAt: iso.string(from: modifiedAt),
            frontmatter: frontmatter,
            headings: headings,
            tags: tags,
            lineRange: lineRange
        )
    }
}

/// Slice the content by 1-based inclusive line numbers, clamping to file bounds.
/// Returns the slice plus the echoed LineRange reflecting the actual clamp.
/// If neither start nor end is provided, returns full content and `nil`.
private func applyLineRange(
    _ content: String,
    start: Int?,
    end: Int?
) -> (String, ReadNoteResult.LineRange?) {
    if start == nil, end == nil {
        return (content, nil)
    }

    let lines = content.components(separatedBy: "\n")
    let total = lines.count

    let rawStart = max(1, start ?? 1)
    let rawEnd = min(total, end ?? total)

    if rawStart > rawEnd || rawStart > total {
        return ("", ReadNoteResult.LineRange(start: rawStart, end: rawEnd))
    }

    let slice = lines[(rawStart - 1)..<rawEnd].joined(separator: "\n")
    return (slice, ReadNoteResult.LineRange(start: rawStart, end: rawEnd))
}
