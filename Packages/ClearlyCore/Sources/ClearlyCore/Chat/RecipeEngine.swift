import Foundation

/// Helpers for loading recipes. Defaults live in the app bundle and the
/// caller passes the markdown string in via `loadDefault`. Vault-local
/// `.clearly/recipes/<slug>.md` overrides are still supported via
/// `loadFromVault` — useful if a user wants to tweak the chat prompt
/// without rebuilding the app — but no shipping path uses it today.
public enum RecipeEngine {

    public static let folderName = ".clearly/recipes"

    public static func slug(for kind: RecipeKind) -> String {
        kind.rawValue
    }

    public static func recipeURL(for kind: RecipeKind, vaultRoot: URL) -> URL {
        vaultRoot
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("\(slug(for: kind)).md")
    }

    public static func loadFromVault(
        _ kind: RecipeKind,
        vaultRoot: URL,
        fileManager: FileManager = .default
    ) throws -> Recipe? {
        let url = recipeURL(for: kind, vaultRoot: vaultRoot)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let markdown = try readUTF8(at: url)
        return try RecipeParser.parse(markdown)
    }

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
