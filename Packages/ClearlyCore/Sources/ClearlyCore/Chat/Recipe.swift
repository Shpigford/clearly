import Foundation

/// Kind of recipe. Today only `chat` exists; the enum is here to keep the
/// frontmatter `kind:` validation working and to leave room for future
/// recipes (e.g. on-demand summarize).
public enum RecipeKind: String, Codable, Sendable, CaseIterable {
    case chat
}

/// A named prompt-template + metadata for a chat recipe. Recipes are plain
/// markdown with YAML frontmatter; users can edit them in place by opening
/// the file in the editor — no app-side schema migrations.
public struct Recipe: Equatable, Sendable {
    public let name: String
    public let description: String
    public let kind: RecipeKind
    public let toolAllowlist: [String]
    public let expectedOutput: String
    public let prompt: String

    public init(
        name: String,
        description: String,
        kind: RecipeKind,
        toolAllowlist: [String],
        expectedOutput: String,
        prompt: String
    ) {
        self.name = name
        self.description = description
        self.kind = kind
        self.toolAllowlist = toolAllowlist
        self.expectedOutput = expectedOutput
        self.prompt = prompt
    }
}

public enum RecipeError: Error, Equatable, Sendable {
    case missingFrontmatter
    case missingField(String)
    case unknownKind(String)
    case secretReference(token: String)
    case unknownToken(token: String)
    case fileNotFound(path: String)
    case encodingFailure
}

public enum RecipeParser {

    public static let allowedTokens: Set<String> = ["input", "vault_state"]

    public static func parse(_ markdown: String) throws -> Recipe {
        guard let block = FrontmatterSupport.extract(from: markdown) else {
            throw RecipeError.missingFrontmatter
        }
        let fields = Dictionary(uniqueKeysWithValues: block.fields.map { ($0.key, $0.value) })

        guard let name = fields["name"], !name.isEmpty else {
            throw RecipeError.missingField("name")
        }
        let description = fields["description"] ?? ""
        guard let rawKind = fields["kind"], !rawKind.isEmpty else {
            throw RecipeError.missingField("kind")
        }
        guard let kind = RecipeKind(rawValue: rawKind) else {
            throw RecipeError.unknownKind(rawKind)
        }
        let toolAllowlist = parseList(fields["tool_allowlist"])
        let expectedOutput = fields["expected_output"] ?? ""

        let prompt = block.body.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateTokens(in: prompt)

        return Recipe(
            name: name,
            description: description,
            kind: kind,
            toolAllowlist: toolAllowlist,
            expectedOutput: expectedOutput,
            prompt: prompt
        )
    }

    public static func interpolate(
        _ recipe: Recipe,
        input: String,
        vaultState: String
    ) -> String {
        let source = recipe.prompt as NSString
        let result = NSMutableString(string: recipe.prompt)
        let range = NSRange(location: 0, length: source.length)
        for match in tokenRegex.matches(in: recipe.prompt, range: range).reversed() {
            let token = source.substring(with: match.range(at: 1))
            let replacement: String?
            switch token {
            case "input": replacement = input
            case "vault_state": replacement = vaultState
            default: replacement = nil
            }
            if let replacement {
                result.replaceCharacters(in: match.range, with: replacement)
            }
        }
        return String(result)
    }

    // MARK: - Private

    private static func parseList(_ raw: String?) -> [String] {
        guard let raw = raw, !raw.isEmpty else { return [] }
        let stripped = raw
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        let separators = CharacterSet(charactersIn: ",\n")
        return stripped
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "-\"'")) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func validateTokens(in prompt: String) throws {
        let range = NSRange(prompt.startIndex..<prompt.endIndex, in: prompt)
        let matches = tokenRegex.matches(in: prompt, range: range)
        for match in matches {
            guard let tokenRange = Range(match.range(at: 1), in: prompt) else { continue }
            let token = String(prompt[tokenRange])
            if looksLikeSecretName(token) {
                throw RecipeError.secretReference(token: token)
            }
            guard allowedTokens.contains(token) else {
                throw RecipeError.unknownToken(token: token)
            }
        }
    }

    private static func looksLikeSecretName(_ token: String) -> Bool {
        let lowered = token.lowercased()
        let banned: Set<String> = ["key", "secret", "password", "credential", "credentials", "env"]
        let segments = lowered.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return segments.contains { banned.contains(String($0)) }
    }

    private static let tokenRegex = try! NSRegularExpression(pattern: #"\{\{\s*([^}\s]+)\s*\}\}"#)
}
