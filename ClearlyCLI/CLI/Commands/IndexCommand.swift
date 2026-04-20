import ArgumentParser
import ClearlyCore
import Foundation

struct IndexCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "index",
        abstract: "Vault index maintenance.",
        discussion: """
        Parent command for index operations. Currently exposes `rebuild`
        only. Running `clearly index` with no subcommand is equivalent to
        `clearly index rebuild`.

        EXAMPLES
          clearly index                        # same as `clearly index rebuild`
          clearly index rebuild --in-vault Work
        """,
        subcommands: [IndexRebuildCommand.self],
        defaultSubcommand: IndexRebuildCommand.self
    )
}

// MARK: - index rebuild

private struct RebuiltVault: Encodable {
    let name: String
    let path: String
    let durationMs: Int
}

private struct RebuildResult: Encodable {
    let rebuilt: Bool
    let vaults: [RebuiltVault]
}

struct IndexRebuildCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rebuild",
        abstract: "Rebuild the SQLite index from disk. Pass --in-vault to limit to one vault.",
        discussion: """
        Full re-walk of each vault's filesystem, re-hashing every markdown
        file. Use this to recover from a corrupted index or after
        out-of-band file operations. One-liner stderr per vault; final
        JSON summary on stdout with per-vault duration_ms.

        Exits 3 / error no_vault_match if --in-vault doesn't match any
        loaded vault.

        EXAMPLES
          # Rebuild every loaded vault
          clearly index rebuild

          # Rebuild only one (matched on directory name)
          clearly index rebuild --in-vault Documents
        """
    )

    @OptionGroup var globals: GlobalOptions

    @Option(
        name: .customLong("in-vault"),
        help: "Restrict rebuild to the vault whose directory name matches."
    )
    var inVault: String?

    func run() async throws {
        let vaults: [LoadedVault]
        do {
            vaults = try IndexSet.openIndexes(globals)
        } catch {
            Emitter.emitError(
                "no_vaults",
                message: "Unable to open any vault index: \(error.localizedDescription)",
                extra: ["bundle_id": globals.bundleID]
            )
            throw ExitCode(Exit.general)
        }

        let targets: [LoadedVault]
        if let filter = inVault {
            targets = vaults.filter { $0.url.lastPathComponent == filter }
            if targets.isEmpty {
                Emitter.emitError(
                    "no_vault_match",
                    message: "No loaded vault matches --in-vault \(filter).",
                    extra: ["filter": filter]
                )
                throw ExitCode(Exit.notFound)
            }
        } else {
            targets = vaults
        }

        var rebuilt: [RebuiltVault] = []
        for vault in targets {
            let name = vault.url.lastPathComponent
            FileHandle.standardError.write(
                Data("Rebuilding \(name)\u{2026}\n".utf8)
            )
            let start = Date()
            vault.index.indexAllFiles()
            let elapsedMs = Int((Date().timeIntervalSince(start) * 1000).rounded())
            rebuilt.append(RebuiltVault(name: name, path: vault.url.path, durationMs: elapsedMs))
        }

        let result = RebuildResult(rebuilt: true, vaults: rebuilt)
        switch globals.format {
        case .json:
            try Emitter.emit(result, format: .json)
        case .text:
            for entry in rebuilt {
                Emitter.emitLine("\(entry.name)\t\(entry.durationMs)ms")
            }
        }
    }
}
