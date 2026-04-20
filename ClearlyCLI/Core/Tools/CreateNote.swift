import Foundation
import ClearlyCore
import CryptoKit

struct CreateNoteArgs: Codable {
    let relativePath: String
    let content: String
    let vault: String?
}

struct CreateNoteResult: Codable {
    let vault: String
    let relativePath: String
    let contentHash: String
    let sizeBytes: Int
    let createdAt: String
}

func createNote(_ args: CreateNoteArgs, vaults: [LoadedVault]) async throws -> CreateNoteResult {
    guard !args.relativePath.isEmpty else {
        throw ToolError.missingArgument("relative_path")
    }

    let loaded: LoadedVault
    switch try VaultResolver.resolveForWrite(relativePath: args.relativePath, hint: args.vault, in: vaults) {
    case .notFound:
        throw ToolError.invalidArgument(name: "vault", reason: "no loaded vault matches '\(args.vault ?? "")'")
    case .ambiguous(let matches):
        throw ToolError.ambiguousVault(
            relativePath: args.relativePath,
            matches: matches.map { $0.url.lastPathComponent }
        )
    case .resolved(let v):
        loaded = v
    }

    let fileURL = try PathGuard.resolve(relativePath: args.relativePath, in: loaded.url)

    if FileManager.default.fileExists(atPath: fileURL.path) {
        throw ToolError.conflict(existingPath: args.relativePath)
    }

    let parentDir = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

    let data = Data(args.content.utf8)
    try data.write(to: fileURL, options: .atomic)

    try loaded.index.updateFile(at: args.relativePath)

    let filename = fileURL.deletingPathExtension().lastPathComponent
    try loaded.index.resolveLinksToFile(named: filename)

    let hash = SHA256.hash(data: data)
    let contentHash = hash.map { String(format: "%02x", $0) }.joined()
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    return CreateNoteResult(
        vault: loaded.url.lastPathComponent,
        relativePath: args.relativePath,
        contentHash: contentHash,
        sizeBytes: data.count,
        createdAt: iso.string(from: Date())
    )
}
