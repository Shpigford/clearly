import ArgumentParser
import Foundation

struct VaultsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vaults",
        abstract: "List configured vaults.",
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
        abstract: "List loaded vaults as NDJSON (one record per line)."
    )

    @OptionGroup var globals: GlobalOptions

    func run() async throws {
        let vaults: [LoadedVault]
        do {
            vaults = try IndexSet.openIndexes(globals)
        } catch {
            Emitter.emitError(
                "no_vaults",
                message: "Unable to open any vault index: \(error.localizedDescription)"
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
        abstract: "Add a vault. Not available here — use the Clearly app (the sync feature will expose this)."
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
        abstract: "Remove a vault. Not available here — use the Clearly app (the sync feature will expose this)."
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
