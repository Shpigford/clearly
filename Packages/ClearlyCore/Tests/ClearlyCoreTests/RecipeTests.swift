import XCTest
@testable import ClearlyCore

final class RecipeTests: XCTestCase {

    // MARK: - Parse

    func testParsesMinimalRecipe() throws {
        let source = """
        ---
        name: Ingest
        description: Summarise a source
        kind: capture
        tool_allowlist: [search_notes, propose_operation]
        expected_output: wiki_operation
        ---
        Source: {{input}}
        Vault: {{vault_state}}
        """
        let recipe = try RecipeParser.parse(source)
        XCTAssertEqual(recipe.name, "Ingest")
        XCTAssertEqual(recipe.description, "Summarise a source")
        XCTAssertEqual(recipe.kind, .capture)
        XCTAssertEqual(recipe.toolAllowlist, ["search_notes", "propose_operation"])
        XCTAssertEqual(recipe.expectedOutput, "wiki_operation")
        XCTAssertTrue(recipe.prompt.contains("{{input}}"))
    }

    func testParsesBlockListAllowlist() throws {
        let source = """
        ---
        name: Lint
        kind: review
        tool_allowlist:
          - search_notes
          - list_orphans
        ---
        Body {{input}}
        """
        let recipe = try RecipeParser.parse(source)
        XCTAssertEqual(recipe.toolAllowlist, ["search_notes", "list_orphans"])
    }

    func testRejectsMissingFrontmatter() {
        let source = "No frontmatter here. {{input}}"
        XCTAssertThrowsError(try RecipeParser.parse(source)) { error in
            XCTAssertEqual(error as? RecipeError, .missingFrontmatter)
        }
    }

    func testRejectsMissingName() {
        let source = """
        ---
        kind: capture
        ---
        {{input}}
        """
        XCTAssertThrowsError(try RecipeParser.parse(source)) { error in
            XCTAssertEqual(error as? RecipeError, .missingField("name"))
        }
    }

    func testRejectsUnknownKind() {
        let source = """
        ---
        name: Bogus
        kind: wombat
        ---
        {{input}}
        """
        XCTAssertThrowsError(try RecipeParser.parse(source)) { error in
            XCTAssertEqual(error as? RecipeError, .unknownKind("wombat"))
        }
    }

    // MARK: - Token policy

    func testRejectsSecretNamedToken() {
        let source = """
        ---
        name: X
        kind: capture
        ---
        My key is {{api_key}}
        """
        XCTAssertThrowsError(try RecipeParser.parse(source)) { error in
            XCTAssertEqual(error as? RecipeError, .secretReference(token: "api_key"))
        }
    }

    func testRejectsUnknownToken() {
        let source = """
        ---
        name: X
        kind: capture
        ---
        Here is {{some_other_token}}
        """
        XCTAssertThrowsError(try RecipeParser.parse(source)) { error in
            XCTAssertEqual(error as? RecipeError, .unknownToken(token: "some_other_token"))
        }
    }

    func testAcceptsAllowedTokens() throws {
        let source = """
        ---
        name: X
        kind: chat
        ---
        q={{input}} state={{vault_state}}
        """
        XCTAssertNoThrow(try RecipeParser.parse(source))
    }

    // MARK: - Interpolation

    func testInterpolatesAllowedTokens() throws {
        let recipe = try RecipeParser.parse("""
        ---
        name: X
        kind: capture
        ---
        q={{input}} s={{vault_state}}
        """)
        let out = RecipeParser.interpolate(recipe, input: "hi", vaultState: "[files]")
        XCTAssertEqual(out, "q=hi s=[files]")
    }

    // MARK: - Engine disk IO

    func testEngineReturnsNilWhenRecipeMissing() throws {
        let vault = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: vault) }
        XCTAssertNil(try RecipeEngine.loadFromVault(.capture, vaultRoot: vault))
    }

    func testEngineLoadsVaultRecipe() throws {
        let vault = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: vault) }
        let recipesDir = vault.appendingPathComponent(".clearly/recipes", isDirectory: true)
        try FileManager.default.createDirectory(at: recipesDir, withIntermediateDirectories: true)
        try """
        ---
        name: Custom
        kind: capture
        ---
        Body {{input}}
        """.write(
            to: recipesDir.appendingPathComponent("capture.md"),
            atomically: true, encoding: .utf8
        )
        let recipe = try RecipeEngine.loadFromVault(.capture, vaultRoot: vault)
        XCTAssertEqual(recipe?.name, "Custom")
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recipe-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
