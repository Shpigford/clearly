import Foundation
import AppKit
import ClearlyCore

/// Seeds a vault folder with the LLM Wiki marker files + `raw/` + recipes.
///
/// Copies `AGENTS.md`, `index.md`, `log.md`, `raw/README.md` from the
/// bundled `wiki-template/` folder. Skips any file that already exists so
/// "Convert to LLM Wiki" on an existing vault never overwrites content.
enum WikiSeeder {
    enum Error: Swift.Error {
        case templateMissing
        case writeFailed(underlying: Swift.Error)
    }

    /// Files that must be present for Clearly to classify the vault as a wiki.
    /// Kept in sync with `WikiMarker.allCases`.
    static let markerFilenames: [String] = WikiMarker.allCases.map(\.rawValue)

    /// Seed `folder` with wiki template files. Existing files are left alone.
    static func seed(at folder: URL) throws {
        guard let templateURL = Bundle.main.url(forResource: "wiki-template", withExtension: nil) else {
            throw Error.templateMissing
        }

        let fm = FileManager.default
        let entries: [(src: URL, dst: URL)] = [
            (templateURL.appendingPathComponent("AGENTS.md"),
             folder.appendingPathComponent("AGENTS.md")),
            (templateURL.appendingPathComponent("index.md"),
             folder.appendingPathComponent("index.md")),
            (templateURL.appendingPathComponent("log.md"),
             folder.appendingPathComponent("log.md")),
            (templateURL.appendingPathComponent("getting-started.md"),
             folder.appendingPathComponent("getting-started.md")),
            (templateURL.appendingPathComponent("raw/README.md"),
             folder.appendingPathComponent("raw/README.md")),
        ]

        // Ensure raw/ exists before attempting to write into it.
        let rawFolder = folder.appendingPathComponent("raw")
        if !fm.fileExists(atPath: rawFolder.path) {
            do {
                try fm.createDirectory(at: rawFolder, withIntermediateDirectories: true)
            } catch {
                throw Error.writeFailed(underlying: error)
            }
        }

        for (src, dst) in entries {
            if fm.fileExists(atPath: dst.path) { continue }
            do {
                try fm.copyItem(at: src, to: dst)
            } catch {
                throw Error.writeFailed(underlying: error)
            }
        }

        try seedRecipes(at: folder)
    }

    /// Copy bundled default recipes into `.clearly/recipes/`. Existing files
    /// are left alone so user edits are never stomped on re-seed.
    private static func seedRecipes(at folder: URL) throws {
        guard let recipesBundleURL = Bundle.main.url(forResource: "recipes", withExtension: nil) else {
            // No bundled recipes — likely running in a test / tooling context.
            // Silent skip is fine here since the engine falls back gracefully.
            return
        }
        let fm = FileManager.default
        let dstDir = folder.appendingPathComponent(".clearly/recipes", isDirectory: true)
        if !fm.fileExists(atPath: dstDir.path) {
            do {
                try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)
            } catch {
                throw Error.writeFailed(underlying: error)
            }
        }

        let names = ["capture.md", "chat.md", "review.md"]
        for name in names {
            let src = recipesBundleURL.appendingPathComponent(name)
            let dst = dstDir.appendingPathComponent(name)
            guard fm.fileExists(atPath: src.path) else { continue }
            if fm.fileExists(atPath: dst.path) { continue }
            do {
                try fm.copyItem(at: src, to: dst)
            } catch {
                throw Error.writeFailed(underlying: error)
            }
        }
    }

    /// Convenience: returns true if the folder already looks like a wiki.
    static func isWikiFolder(_ folder: URL) -> Bool {
        VaultKind.detect(at: folder).isWiki
    }

    /// Drive the full "New LLM Wiki" flow: prompt for a folder, seed the
    /// template + recipes into it, register it as a Clearly vault. Safe to
    /// call from any menu/button action — all UI is NSOpenPanel/NSAlert.
    @MainActor
    static func createNewWiki(using workspace: WorkspaceManager) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose a folder for your new LLM Wiki"
        panel.prompt = "Create Wiki Here"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        if workspace.locations.contains(where: { $0.url == url }) {
            // Already registered — just reseed (no-op on existing files) and
            // refresh the tree so the [wiki] badge appears once markers land.
            do { try seed(at: url) } catch { presentSeedError(error) }
            if let location = workspace.locations.first(where: { $0.url == url }) {
                workspace.refreshTree(for: location.id)
            }
            workspace.isSidebarVisible = true
            UserDefaults.standard.set(true, forKey: "sidebarVisible")
            return
        }

        do {
            try seed(at: url)
        } catch {
            presentSeedError(error)
            return
        }

        _ = workspace.addLocation(url: url)
        workspace.isSidebarVisible = true
        UserDefaults.standard.set(true, forKey: "sidebarVisible")
        workspace.openFile(at: url.appendingPathComponent("getting-started.md"))
    }

    private static func presentSeedError(_ error: Swift.Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't create LLM Wiki"
        alert.informativeText = "Clearly failed to seed template files: \(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.runModal()
    }
}
