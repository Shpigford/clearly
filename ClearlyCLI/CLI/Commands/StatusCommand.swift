import ArgumentParser
import ClearlyCore
import Foundation

private struct VaultStatus: Encodable {
    let name: String
    let path: String
    let fileCount: Int
    let lastIndexedAt: String?
}

private struct StatusReport: Encodable {
    let binaryVersion: String
    let bundleId: String
    let embeddingModelVersion: Int
    let vaultCount: Int
    let vaults: [VaultStatus]
}

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Print binary, vault, and index diagnostics as a single JSON document.",
        discussion: """
        One-shot diagnostic snapshot of the CLI process. Reports binary
        version, configured bundle id, embedding model version, every
        loaded vault with file count and last-indexed timestamp.

        Unlike `clearly vaults list` (which streams NDJSON for piping),
        `status` emits a single JSON object — intended for support tickets,
        debug captures, and human eyeballing.

        EXAMPLES
          # JSON snapshot
          clearly status

          # Vault count only
          clearly status | jq '.vault_count'

          # Human-readable
          clearly status --format text
        """
    )

    @OptionGroup var globals: GlobalOptions

    func run() async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var vaultStatuses: [VaultStatus] = []
        if let loaded = try? IndexSet.openIndexes(globals) {
            vaultStatuses = loaded.map { vault in
                VaultStatus(
                    name: vault.url.lastPathComponent,
                    path: vault.url.path,
                    fileCount: vault.index.fileCount(),
                    lastIndexedAt: vault.index.lastIndexedAt().map { formatter.string(from: $0) }
                )
            }
        }

        let binaryVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"

        let report = StatusReport(
            binaryVersion: binaryVersion,
            bundleId: globals.bundleID,
            embeddingModelVersion: EmbeddingService.MODEL_VERSION,
            vaultCount: vaultStatuses.count,
            vaults: vaultStatuses
        )

        switch globals.format {
        case .json:
            try Emitter.emit(report, format: .json)
        case .text:
            Emitter.emitLine("clearly \(report.binaryVersion)")
            Emitter.emitLine("bundle id:               \(report.bundleId)")
            Emitter.emitLine("embedding model version: \(report.embeddingModelVersion)")
            Emitter.emitLine("vaults loaded:           \(report.vaultCount)")
            for vault in report.vaults {
                Emitter.emitLine("")
                Emitter.emitLine("  \(vault.name)")
                Emitter.emitLine("    path:            \(vault.path)")
                Emitter.emitLine("    file count:      \(vault.fileCount)")
                Emitter.emitLine("    last indexed at: \(vault.lastIndexedAt ?? "—")")
            }
        }
    }
}
