import Foundation
import ClearlyCore

/// Drives the Log Sidebar. Holds the parsed log.md entries + visibility flag.
/// Refreshes are explicit (show / reload / after-apply) — we don't run a
/// file watcher, since the user's own edits to log.md typically come through
/// the editor and FSEvents will already have fired a tree refresh.
@Observable
@MainActor
final class WikiLogState {
    var isVisible: Bool = false
    var entries: [WikiLogEntry] = []
    var lastError: String?

    func toggle(vaultRoot: URL?) {
        isVisible.toggle()
        if isVisible { reload(vaultRoot: vaultRoot) }
    }

    func show(vaultRoot: URL?) {
        isVisible = true
        reload(vaultRoot: vaultRoot)
    }

    func hide() { isVisible = false }

    func reload(vaultRoot: URL?) {
        guard let vaultRoot else {
            entries = []
            lastError = nil
            return
        }
        let logURL = vaultRoot.appendingPathComponent(WikiLogWriter.filename)
        do {
            guard FileManager.default.fileExists(atPath: logURL.path) else {
                entries = []
                lastError = nil
                return
            }
            let text = try String(contentsOf: logURL, encoding: .utf8)
            entries = WikiLogParser.parse(text)
            lastError = nil
        } catch {
            entries = []
            lastError = String(describing: error)
        }
    }
}
