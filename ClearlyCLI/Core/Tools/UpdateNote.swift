import Foundation
import ClearlyCore
import CryptoKit

enum UpdateMode: String, CaseIterable, Codable {
    case replace
    case append
    case prepend
}

struct UpdateNoteArgs: Codable {
    let relativePath: String
    let content: String
    let mode: UpdateMode
    let vault: String?
    /// Optional optimistic-concurrency guard. When provided, the tool
    /// hashes the on-disk file before writing and rejects the call if the
    /// hash doesn't match — protecting against the user (or another
    /// agent) editing the file between the agent's last read and this
    /// write. Omit to skip the check.
    let expectedContentHash: String?
}

struct UpdateNoteResult: Codable {
    let vault: String
    let relativePath: String
    let mode: String
    let contentHash: String
    let sizeBytes: Int
    let modifiedAt: String
}

func updateNote(_ args: UpdateNoteArgs, vaults: [LoadedVault]) async throws -> UpdateNoteResult {
    guard !args.relativePath.isEmpty else {
        throw ToolError.missingArgument("relative_path")
    }

    let loaded: LoadedVault
    switch try VaultResolver.resolve(relativePath: args.relativePath, hint: args.vault, in: vaults) {
    case .notFound:
        throw ToolError.noteNotFound(args.relativePath)
    case .ambiguous(let matches):
        throw ToolError.ambiguousVault(
            relativePath: args.relativePath,
            matches: matches.map { $0.url.lastPathComponent }
        )
    case .resolved(let v):
        loaded = v
    }

    let fileURL = try PathGuard.resolve(relativePath: args.relativePath, in: loaded.url)

    let rawData = try CoordinatedFileIO.read(at: fileURL)
    let actualHash = sha256Hex(rawData)
    if let expected = args.expectedContentHash, expected != actualHash {
        throw ToolError.staleContent(
            relativePath: args.relativePath,
            expected: expected,
            actual: actualHash
        )
    }
    guard let existing = String(data: rawData, encoding: .utf8) else {
        throw ToolError.invalidEncoding(args.relativePath)
    }

    let composed: String
    switch args.mode {
    case .replace:
        composed = args.content
    case .append:
        let separator = existing.hasSuffix("\n") ? "" : "\n"
        composed = existing + separator + args.content
    case .prepend:
        if let block = FrontmatterSupport.extract(from: existing) {
            composed = "---\n" + block.rawText + "\n---\n" + args.content + "\n" + block.body
        } else {
            composed = args.content + "\n" + existing
        }
    }

    let newData = Data(composed.utf8)
    try CoordinatedFileIO.write(newData, to: fileURL)

    try loaded.index.updateFile(at: args.relativePath)

    let contentHash = sha256Hex(newData)

    let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
    let modifiedAt = (attrs?[.modificationDate] as? Date) ?? Date()
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    return UpdateNoteResult(
        vault: loaded.url.lastPathComponent,
        relativePath: args.relativePath,
        mode: args.mode.rawValue,
        contentHash: contentHash,
        sizeBytes: newData.count,
        modifiedAt: iso.string(from: modifiedAt)
    )
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
