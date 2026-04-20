import ArgumentParser
import ClearlyCore
import Foundation

struct VaultsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vaults",
        abstract: "List configured vaults.",
        discussion: """
        Parent command for vault inspection. Run with no subcommand (or
        `list`) to emit one NDJSON record per loaded vault. `add` / `remove`
        are reserved for the sync feature — today they print a pointer to
        the Clearly app and exit 2.

        EXAMPLES
          clearly vaults                     # same as `clearly vaults list`
          clearly vaults list --format text  # vault name, path, file count (tabs)
        """,
        subcommands: [VaultsListCommand.self, VaultsAddCommand.self, VaultsRemoveCommand.self],
        defaultSubcommand: VaultsListCommand.self
    )
}

// MARK: - vaults list

private struct VaultSummary: Encodable {
    let name: String
    let path: String
    let fileCount: Int
    let lastIndexedAt: String?
    let bundleId: String
}

struct VaultsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List loaded vaults as NDJSON (one record per line).",
        discussion: """
        Emits {name, path, file_count, last_indexed_at, bundle_id} per
        vault. `last_indexed_at` is an ISO-8601 timestamp (fractional
        seconds) or null when the index is empty.

        EXAMPLES
          clearly vaults list
          clearly vaults list | jq -r '.name + "\\t" + (.file_count|tostring)'
        """
    )

    @OptionGroup var globals: GlobalOptions

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

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let summaries: [VaultSummary] = vaults.map { vault in
            let lastIndexed = vault.index.lastIndexedAt().map { formatter.string(from: $0) }
            return VaultSummary(
                name: vault.url.lastPathComponent,
                path: vault.url.path,
                fileCount: vault.index.fileCount(),
                lastIndexedAt: lastIndexed,
                bundleId: globals.bundleID
            )
        }

        switch globals.format {
        case .json:
            for summary in summaries {
                try Emitter.emitNDJSONRecord(summary)
            }
        case .text:
            for summary in summaries {
                Emitter.emitLine("\(summary.name)\t\(summary.path)\t\(summary.fileCount)")
            }
        }
    }
}

// MARK: - vaults add / remove (deferred to sync feature)

struct VaultsAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a vault. Not available here — use the Clearly app (the sync feature will expose this).",
        discussion: """
        Placeholder for the sync feature. Today, vault configuration lives
        in the Clearly Mac app (Settings → Vaults). This command exits 2
        and prints a pointer.
        """
    )

    @Argument(help: "Vault path (ignored; open Clearly to manage vaults).")
    var path: String?

    func run() async throws {
        FileHandle.standardError.write(
            Data("Open Clearly to manage vaults.\n".utf8)
        )
        throw ExitCode(Exit.usage)
    }
}

struct VaultsRemoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a vault. Not available here — use the Clearly app (the sync feature will expose this).",
        discussion: """
        Placeholder for the sync feature. Today, vault configuration lives
        in the Clearly Mac app (Settings → Vaults). This command exits 2
        and prints a pointer.
        """
    )

    @Argument(help: "Vault path (ignored; open Clearly to manage vaults).")
    var path: String?

    func run() async throws {
        FileHandle.standardError.write(
            Data("Open Clearly to manage vaults.\n".utf8)
        )
        throw ExitCode(Exit.usage)
    }
}
