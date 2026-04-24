import Foundation
import AppKit
import ClearlyCore

/// Runs the full `Wiki → Ingest` flow. Prompts for URL, fetches it, loads the
/// Ingest recipe, calls the agent, and stages the resulting WikiOperation on
/// the shared `WikiOperationController` so the diff sheet appears. All UI
/// interaction is modal-NSAlert for V1 — a proper SwiftUI sheet can replace
/// the prompts later without touching the coordinator contract.
@MainActor
enum IngestCoordinator {

    /// Approximate cap on HTML we send to the agent. Picked conservatively so
    /// a single ingest with a verbose source stays well under Claude's
    /// context limit once prompt + vault state are added.
    static let maxSourceCharacters = 60_000

    static func start(
        workspace: WorkspaceManager,
        controller: WikiOperationController
    ) {
        guard let vaultURL = workspace.activeLocation?.url,
              workspace.activeVaultIsWiki else {
            presentError("Ingest is only available when the active note lives in a wiki vault.")
            return
        }

        // CLI is the default path — user's Claude Pro / Max sub drives the
        // call, no API key needed. We only ever prompt for an API key if the
        // CLI isn't installed AND the user has no saved key.
        guard let runner = resolveRunner() else {
            presentError("""
            Install Claude Code to use Ingest: https://docs.claude.com/claude-code

            If you'd rather use a direct Anthropic API key, choose Wiki → Set API Key…
            """)
            return
        }

        guard let rawURL = promptText(
            title: "Ingest",
            message: "Paste a URL to summarise into a new note.",
            placeholder: "https://..."
        ), let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }

        Task { @MainActor in
            await runIngest(url: url, vaultURL: vaultURL, workspace: workspace, controller: controller, runner: runner)
        }
    }

    // MARK: - Runner resolution

    private static func resolveRunner() -> AgentRunner? {
        if let cli = AgentDiscovery.findClaude() {
            return ClaudeCLIAgentRunner(binaryURL: cli.url)
        }
        if let cli = AgentDiscovery.findCodex() {
            // Codex CLI parity comes in a later phase; for now, surfacing its
            // presence helps users understand why Ingest might still work
            // without Claude Code installed.
            _ = cli
        }
        let keychain = KeychainStore()
        let key = (try? keychain.get(WikiKeychainAccount.anthropicAPIKey)) ?? nil
        if let key, !key.isEmpty {
            return AnthropicAPIAgentRunner()
        }
        return nil
    }

    /// Public entry point for the "Wiki → Set API Key…" menu item — lets the
    /// user opt into the BYOK fallback explicitly rather than having it
    /// prompted automatically.
    static func promptForAPIKey() {
        let keychain = KeychainStore()
        guard let key = promptSecret(
            title: "Set Anthropic API Key",
            message: "Stored in Keychain. Only used when the Claude CLI isn't installed."
        ), !key.isEmpty else { return }
        do {
            try keychain.set(key, forKey: WikiKeychainAccount.anthropicAPIKey)
        } catch {
            presentError("Couldn't save to Keychain: \(error)")
        }
    }

    // MARK: - Pipeline

    private static func runIngest(
        url: URL,
        vaultURL: URL,
        workspace: WorkspaceManager,
        controller: WikiOperationController,
        runner: AgentRunner
    ) async {
        let fetchURL = rewriteForContent(url)
        DiagnosticLog.log("Ingest: start url=\(url.absoluteString) fetchURL=\(fetchURL.absoluteString)")
        do {
            let sourceText = try await fetchURLContent(fetchURL)
            DiagnosticLog.log("Ingest: fetched \(sourceText.count) chars")
            let recipe = try loadIngestRecipe(vaultURL: vaultURL)
            let vaultState = buildVaultState(vaultURL: vaultURL)
            let input = """
            URL: \(url.absoluteString)

            Content (truncated if >\(maxSourceCharacters) chars):
            \(sourceText.prefix(maxSourceCharacters))
            """
            let prompt = RecipeParser.interpolate(recipe, input: input, vaultState: vaultState)
            DiagnosticLog.log("Ingest: calling agent (prompt=\(prompt.count) chars)")

            let model = UserDefaults.standard.string(forKey: "wikiAgentModel")
            let result = try await runner.run(prompt: prompt, model: model)
            DiagnosticLog.log("Ingest: agent replied \(result.text.count) chars, tokens in=\(result.inputTokens) out=\(result.outputTokens)")

            let operation = try AgentResultParser.parseWikiOperation(from: result.text, kind: .ingest)
            let titled = WikiOperation(
                id: operation.id,
                kind: operation.kind,
                title: "Ingest: \(url.host ?? url.absoluteString)",
                rationale: operation.rationale,
                changes: operation.changes,
                createdAt: operation.createdAt
            )
            DiagnosticLog.log("Ingest: staging operation with \(titled.changes.count) changes")
            controller.stage(titled)
        } catch {
            DiagnosticLog.log("Ingest failed: \(error)")
            presentError("Ingest failed: \(Self.describe(error))")
        }
    }

    // MARK: - URL rewrites

    /// Rewrite URLs whose default HTML is a thin shell into a form that
    /// actually contains the content. Currently: GitHub gists — the gist
    /// page loads the body client-side, so `/<user>/<id>` needs to become
    /// `/<user>/<id>/raw` (or first file) to get actual text. Extend per
    /// host as needed.
    static func rewriteForContent(_ url: URL) -> URL {
        guard let host = url.host?.lowercased() else { return url }
        if host == "gist.github.com" {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let parts = path.split(separator: "/").map(String.init)
            // e.g. ["karpathy", "442a6bf555914893e9891c11519de94f"]
            if parts.count == 2,
               let rawURL = URL(string: "https://gist.githubusercontent.com/\(parts[0])/\(parts[1])/raw") {
                return rawURL
            }
        }
        return url
    }

    // MARK: - Vault state

    /// Snapshot of the vault the agent needs to propose a valid `modify`.
    /// Lists every markdown path AND inlines the current `index.md` and
    /// `AGENTS.md` contents verbatim so the agent's `before:` matches disk
    /// exactly. Without this, the agent has to guess and our strict
    /// modifyBaseMismatch check rejects the apply.
    private static func buildVaultState(vaultURL: URL) -> String {
        let paths = listVaultMarkdownPaths(under: vaultURL)
        var lines = ["# Vault files"]
        lines.append(contentsOf: paths)
        lines.append("")

        for filename in ["index.md", "AGENTS.md"] {
            let fileURL = vaultURL.appendingPathComponent(filename)
            if let contents = try? String(contentsOf: fileURL, encoding: .utf8) {
                lines.append("# Current contents of \(filename) — copy verbatim into any `before:` field")
                lines.append("```")
                lines.append(contents)
                lines.append("```")
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Recipe

    private static func loadIngestRecipe(vaultURL: URL) throws -> Recipe {
        if let vaultRecipe = try RecipeEngine.loadFromVault(.ingest, vaultRoot: vaultURL) {
            return vaultRecipe
        }
        guard let bundleURL = Bundle.main.url(forResource: "recipes", withExtension: nil)?
            .appendingPathComponent("ingest.md") else {
            throw RecipeError.fileNotFound(path: "ingest.md")
        }
        let markdown = try String(contentsOf: bundleURL, encoding: .utf8)
        return try RecipeEngine.loadDefault(markdown)
    }

    // MARK: - Vault state

    private static func listVaultMarkdownPaths(under vaultURL: URL) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: vaultURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var results: [String] = []
        for case let url as URL in enumerator {
            guard url.pathExtension.lowercased() == "md" else { continue }
            let full = url.resolvingSymlinksInPath().path
            let root = vaultURL.resolvingSymlinksInPath().path
            guard full.hasPrefix(root) else { continue }
            var relative = String(full.dropFirst(root.count))
            if relative.hasPrefix("/") { relative = String(relative.dropFirst()) }
            results.append(relative)
        }
        return results.sorted()
    }

    // MARK: - URL fetch

    private static func fetchURLContent(_ url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AgentError.httpError(status: status, body: "fetch failed")
        }
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        throw AgentError.invalidResponse("non-text response body")
    }

    // MARK: - NSAlert helpers

    private static func promptText(title: String, message: String, placeholder: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private static func promptSecret(title: String, message: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private static func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Wiki"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case AgentError.missingAPIKey: return "Anthropic API key is missing."
        case AgentError.invalidResponse(let m): return "Invalid response: \(m)"
        case AgentError.httpError(let status, _): return "HTTP \(status) from the API."
        case AgentError.transport(let m): return "Network error: \(m)"
        case AgentError.invalidWikiOperation(let m): return "Agent returned invalid operation: \(m)"
        default: return String(describing: error)
        }
    }
}
