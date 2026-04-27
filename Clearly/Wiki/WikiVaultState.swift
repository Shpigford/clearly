import Foundation
import ClearlyCore

/// Per-vault bookkeeping persisted at `<vault>/.clearly/state.json`. Currently
/// holds only the timestamp of the last successful auto-Review so we can gate
/// the next run by a 24h cooldown.
///
/// Reads fail closed (missing/corrupt/schema-bumped → `nil`), so callers treat
/// "no record" as "stale, re-run". Writes are best-effort; I/O failures log
/// via `DiagnosticLog` and swallow.
struct WikiVaultState: Codable {
    var lastReviewAt: Date?
    var schemaVersion: Int

    static let currentSchemaVersion = 1
    static let directoryName = ".clearly"
    static let fileName = "state.json"

    init(lastReviewAt: Date? = nil, schemaVersion: Int = currentSchemaVersion) {
        self.lastReviewAt = lastReviewAt
        self.schemaVersion = schemaVersion
    }

    static func read(at vaultURL: URL) -> WikiVaultState? {
        let url = stateURL(at: vaultURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(WikiVaultState.self, from: data) else {
            return nil
        }
        guard state.schemaVersion == currentSchemaVersion else { return nil }
        return state
    }

    static func recordReviewRun(at vaultURL: URL, time: Date = Date()) {
        var state = read(at: vaultURL) ?? WikiVaultState()
        state.lastReviewAt = time
        state.schemaVersion = currentSchemaVersion
        write(state, to: vaultURL)
    }

    private static func write(_ state: WikiVaultState, to vaultURL: URL) {
        let dir = vaultURL.appendingPathComponent(directoryName, isDirectory: true)
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: stateURL(at: vaultURL), options: .atomic)
        } catch {
            DiagnosticLog.log("WikiVaultState: write failed — \(error)")
        }
    }

    private static func stateURL(at vaultURL: URL) -> URL {
        vaultURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
