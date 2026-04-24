import Foundation

/// Filesystem-aware helpers for loading recipes. Recipes live in the user's
/// vault under `.clearly/recipes/<slug>.md` — the user can edit them in place.
/// Defaults live in the app bundle and are copied on vault creation; the app
/// layer knows how to reach its own bundle, so loading the default falls to
/// the caller (pass the default markdown in as a string).
public enum RecipeEngine {

    public static let folderName = ".clearly/recipes"

    /// Slug used on disk for each recipe kind. Kept lowercase + extensionless
    /// so paths are predictable across platforms.
    public static func slug(for kind: OperationKind) -> String {
        kind.rawValue
    }

    public static func recipeURL(for kind: OperationKind, vaultRoot: URL) -> URL {
        vaultRoot
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("\(slug(for: kind)).md")
    }

    /// Try to load a vault-local recipe for `kind`. Returns nil if the file
    /// doesn't exist so the caller can fall back to the bundled default.
    /// Throws on parse failure — stale or invalid recipes should never silently
    /// be replaced by defaults (the user's edits would be ignored).
    public static func loadFromVault(
        _ kind: OperationKind,
        vaultRoot: URL,
        fileManager: FileManager = .default
    ) throws -> Recipe? {
        let url = recipeURL(for: kind, vaultRoot: vaultRoot)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let markdown = try readUTF8(at: url)
        return try RecipeParser.parse(markdown)
    }

    /// Parse a bundled default recipe. The app layer passes in the
    /// markdown string it loaded from its own bundle.
    public static func loadDefault(_ markdown: String) throws -> Recipe {
        try RecipeParser.parse(markdown)
    }

    // MARK: - Private

    private static func readUTF8(at url: URL) throws -> String {
        let data = try CoordinatedFileIO.read(at: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw RecipeError.encodingFailure
        }
        return text
    }
}
