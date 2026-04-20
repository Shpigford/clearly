import Foundation
import ClearlyCore

struct GetFrontmatterArgs: Codable {
    let relativePath: String
    let vault: String?
}

struct GetFrontmatterResult: Codable {
    let vault: String
    let relativePath: String
    /// Flat dict of YAML frontmatter fields. Duplicate keys resolve
    /// last-write-wins, matching FileParser's single-logical-value convention.
    let frontmatter: [String: String]
    let hasFrontmatter: Bool
}

func getFrontmatter(_ args: GetFrontmatterArgs, vaults: [LoadedVault]) async throws -> GetFrontmatterResult {
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
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ToolError.noteNotFound(args.relativePath)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ToolError.invalidEncoding(args.relativePath)
        }

        guard let block = FrontmatterSupport.extract(from: text) else {
            return GetFrontmatterResult(
                vault: loaded.url.lastPathComponent,
                relativePath: args.relativePath,
                frontmatter: [:],
                hasFrontmatter: false
            )
        }
        var dict: [String: String] = [:]
        for field in block.fields {
            dict[field.key] = field.value
        }
        return GetFrontmatterResult(
            vault: loaded.url.lastPathComponent,
            relativePath: args.relativePath,
            frontmatter: dict,
            hasFrontmatter: true
        )
    }
}
