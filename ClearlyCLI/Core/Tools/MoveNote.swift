import Foundation
import ClearlyCore

struct MoveNoteArgs: Codable {
    let fromPath: String
    let toPath: String
    let vault: String?
}

struct MoveNoteResult: Codable {
    struct Rewrite: Codable {
        let relativePath: String
        let count: Int
    }
    let vault: String
    let from: String
    let to: String
    let linksRewritten: [Rewrite]
}

/// Move a note within a vault, rewriting every inbound `[[wiki-link]]`
/// to point at the new path. See `VaultMover` for the orchestration —
/// this tool is the MCP/CLI surface.
func moveNote(_ args: MoveNoteArgs, vaults: [LoadedVault]) async throws -> MoveNoteResult {
    guard !args.fromPath.isEmpty else {
        throw ToolError.missingArgument("from_path")
    }
    guard !args.toPath.isEmpty else {
        throw ToolError.missingArgument("to_path")
    }
    if args.fromPath == args.toPath {
        throw ToolError.invalidArgument(name: "to_path", reason: "must differ from from_path")
    }

    let loaded: LoadedVault
    switch try VaultResolver.resolve(relativePath: args.fromPath, hint: args.vault, in: vaults) {
    case .notFound:
        throw ToolError.noteNotFound(args.fromPath)
    case .ambiguous(let matches):
        throw ToolError.ambiguousVault(
            relativePath: args.fromPath,
            matches: matches.map { $0.url.lastPathComponent }
        )
    case .resolved(let v):
        loaded = v
    }

    // Path-traversal validation. Both ends must resolve inside the vault.
    _ = try PathGuard.resolve(relativePath: args.fromPath, in: loaded.url)
    let destURL = try PathGuard.resolve(relativePath: args.toPath, in: loaded.url)
    if FileManager.default.fileExists(atPath: destURL.path) {
        throw ToolError.conflict(existingPath: args.toPath)
    }

    let outcome: VaultMover.Outcome
    do {
        outcome = try VaultMover.move(
            index: loaded.index,
            vaultRootURL: loaded.url,
            oldRelativePath: args.fromPath,
            newRelativePath: args.toPath
        )
    } catch VaultMover.MoveError.sourceNotIndexed {
        throw ToolError.noteNotFound(args.fromPath)
    } catch VaultMover.MoveError.destinationExists(_) {
        throw ToolError.conflict(existingPath: args.toPath)
    }

    return MoveNoteResult(
        vault: loaded.url.lastPathComponent,
        from: args.fromPath,
        to: args.toPath,
        linksRewritten: outcome.linksRewritten.map {
            MoveNoteResult.Rewrite(relativePath: $0.relativePath, count: $0.count)
        }
    )
}
