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
    }

    /// Convenience: returns true if the folder already looks like a wiki.
    static func isWikiFolder(_ folder: URL) -> Bool {
        VaultKind.detect(at: folder).isWiki
    }
}
