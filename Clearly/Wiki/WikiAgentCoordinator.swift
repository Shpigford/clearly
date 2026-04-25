import Foundation
import AppKit
import ClearlyCore

/// Runs `Wiki → Capture / Chat / Review` end-to-end. Each entry point prompts
/// for the right user input, loads the matching recipe, invokes the agent,
/// parses the response into a WikiOperation, and stages it on the shared
/// controller so the diff sheet appears.
///
/// All UI is modal NSAlert for V1 — a proper SwiftUI sheet for input can
/// replace the prompts later without changing the coordinator contract.
@MainActor
enum WikiAgentCoordinator {

    /// Conservative cap on HTML we ship to the agent. Leaves room for the
    /// recipe + vault_state + output budget inside Claude's context window.
    static let maxSourceCharacters = 60_000

    // MARK: - Entry points

    /// Open the Capture sheet, pre-filling the clipboard if it holds a URL.
    /// The actual run happens in `submitCapture(_:)` once the user clicks
    /// the sheet's Capture button.
    static func startCapture(workspace: WorkspaceManager, capture: WikiCaptureState) {
        guard workspace.activeVaultIsWiki, workspace.activeLocation?.url != nil else {
            presentError("Capture is only available when the active note lives in a wiki vault.")
            return
        }
        capture.show(prefill: clipboardStringIfLikelySource())
    }

    /// Called by the Capture sheet when the user submits. Classifies the
    /// raw input, kicks off the agent run, and stages the resulting
    /// WikiOperation on `controller` for diff review.
    static func submitCapture(
        _ raw: String,
        workspace: WorkspaceManager,
        controller: WikiOperationController
    ) {
        guard let session = beginSession(workspace: workspace, operationKind: .capture) else { return }
        let source = classifySource(raw)
        guard source != .empty else { return }

        Task { @MainActor in
            await runRecipe(
                kind: .capture,
                session: session,
                controller: controller,
                startStatus: source.startStatus,
                titleFor: { _ in source.title }
            ) {
                try await source.buildInputBody(maxSourceCharacters: maxSourceCharacters)
            }
        }
    }

    /// Entry point for ⌃⌘Q and the Wiki menu. Shows the chat panel and
    /// focuses the input; the user types from there.
    static func startChat(workspace: WorkspaceManager, chat: WikiChatState) {
        guard let _ = workspace.activeLocation?.url, workspace.activeVaultIsWiki else {
            presentError("Chat is only available when the active note lives in a wiki vault.")
            return
        }
        chat.show()
    }

    /// Called by WikiChatView when the user submits a message. Runs the
    /// query recipe with the full conversation history inlined as `{{input}}`,
    /// appends the assistant's reply, and opportunistically warms the cache
    /// so follow-up turns are fast.
    static func sendChatMessage(
        _ text: String,
        workspace: WorkspaceManager,
        chat: WikiChatState
    ) {
        guard let vaultURL = workspace.activeLocation?.url, workspace.activeVaultIsWiki else {
            presentError("Chat is only available when the active note lives in a wiki vault.")
            return
        }
        // Chat uses a tool-enabled runner pointed at the vault cwd so Claude
        // Code can Read/Grep/Glob on demand — dramatically better synthesis
        // than us dumping 300KB of context upfront. Falls through to the BYOK
        // API runner (no tools) if Claude CLI isn't installed.
        guard let runner = resolveToolEnabledRunner(vaultURL: vaultURL) else {
            presentError("""
            Install Claude Code to use Wiki Chat: https://docs.claude.com/claude-code

            Or choose Wiki → Set Anthropic API Key… to fall back to BYOK (without file-exploration tools).
            """)
            return
        }
        AgentWarmer.warmIfNeeded(runner: runner)

        _ = chat.appendUser(text)
        chat.draft = ""
        chat.isSending = true
        chat.sendError = nil

        Task { @MainActor in
            defer { chat.isSending = false }
            do {
                let recipe = try loadRecipe(kind: .chat, vaultURL: vaultURL)
                // Minimal context pointer — the agent explores with tools
                // instead of us inlining files.
                let vaultState = buildQueryVaultPointer(vaultURL: vaultURL)
                let transcript = Self.renderTranscript(chat.messages)
                let prompt = RecipeParser.interpolate(recipe, input: transcript, vaultState: vaultState)
                DiagnosticLog.log("Chat: sending (turns=\(chat.messages.count), prompt=\(prompt.count) chars)")

                let model = UserDefaults.standard.string(forKey: "wikiAgentModel")
                let result = try await runner.run(prompt: prompt, model: model)
                AgentWarmer.markExercised()
                DiagnosticLog.log("Chat: reply \(result.text.count) chars, tokens in=\(result.inputTokens) out=\(result.outputTokens)")

                let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    chat.sendError = "Empty response from the agent."
                    return
                }
                _ = chat.appendAssistant(trimmed)
            } catch {
                DiagnosticLog.log("Chat failed: \(error)")
                chat.sendError = Self.describe(error)
            }
        }
    }

    /// Short prompt-side pointer that tells the agent how the vault is laid
    /// out and that it should use its native tools. Replaces the 300KB
    /// inline-everything approach — smaller prompt, smarter agent, better
    /// answers because it reads only what's relevant.
    private static func buildQueryVaultPointer(vaultURL: URL) -> String {
        let paths = listVaultMarkdownPaths(under: vaultURL)
        var lines = [
            "# Wiki vault",
            "",
            "Your current working directory IS the user's wiki vault. Every markdown file in it is part of the knowledge base. Use your Read / Grep / Glob tools to explore it:",
            "",
            "- `Glob \"**/*.md\"` — list notes",
            "- `Grep <term>` — search across all notes",
            "- `Read <path>` — load a specific note's contents",
            "",
            "Prefer reading only the files that are actually relevant to the question. Cite what you read as `[[note-name]]` wiki-links.",
            "",
            "Quick inventory (you can also discover these yourself):",
        ]
        lines.append(contentsOf: paths.map { "- \($0)" })
        return lines.joined(separator: "\n")
    }

    /// Serialise the conversation into the form the query recipe expects as
    /// `{{input}}`. We flag the latest message so the model knows which turn
    /// to answer rather than re-summarising the whole history.
    private static func renderTranscript(_ messages: [WikiChatMessage]) -> String {
        var lines: [String] = ["Conversation so far:"]
        for message in messages {
            let role = message.role == .user ? "User" : "Assistant"
            lines.append("\(role): \(message.text)")
        }
        lines.append("")
        lines.append("Answer the most recent User message as Assistant, in plain markdown.")
        return lines.joined(separator: "\n")
    }

    static func startReview(workspace: WorkspaceManager, controller: WikiOperationController) {
        guard let session = beginSession(workspace: workspace, operationKind: .review) else { return }
        // Focus is optional — empty input means "general pass".
        let focus = promptText(
            title: "Review",
            message: "Optional: scope the audit to a topic or folder. Leave blank for a general pass.",
            placeholder: "e.g. llm-training / projects/"
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        Task { @MainActor in
            await runRecipe(
                kind: .review,
                session: session,
                controller: controller,
                startStatus: focus.isEmpty ? "Reviewing the wiki…" : "Reviewing — focus: \(focus)",
                titleFor: { proposal in
                    let count = proposal.changes.count
                    return count == 0
                        ? "Review: no issues"
                        : "Review: \(count) fix\(count == 1 ? "" : "es")"
                }
            ) { focus }
        }
    }

    /// Fire a silent cache warmup for the chat/query path as soon as a wiki
    /// vault becomes active. CLI-only (Pro/Max sub = free) — we skip API-key
    /// users since each warmup is a real billable call. Safe to call
    /// repeatedly; AgentWarmer short-circuits while the cache is still warm.
    static func warmForActiveVaultIfPossible(workspace: WorkspaceManager) {
        guard workspace.activeVaultIsWiki,
              let vaultURL = workspace.activeLocation?.url,
              let cli = AgentDiscovery.findClaude() else {
            return
        }
        let runner = ClaudeCLIAgentRunner(
            binaryURL: cli.url,
            enabledTools: "Read,Grep,Glob",
            workingDirectory: vaultURL
        )
        AgentWarmer.warmIfNeeded(runner: runner)
    }

    /// Explicit opt-in to the BYOK API fallback. Exposed for the
    /// Wiki → Set Anthropic API Key… menu item.
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

    // MARK: - Session

    private struct Session {
        let vaultURL: URL
        let runner: AgentRunner
    }

    private static func beginSession(
        workspace: WorkspaceManager,
        operationKind: OperationKind
    ) -> Session? {
        guard let vaultURL = workspace.activeLocation?.url, workspace.activeVaultIsWiki else {
            presentError("\(operationKind.rawValue.capitalized) is only available when the active note lives in a wiki vault.")
            return nil
        }
        guard let runner = resolveToolEnabledRunner(vaultURL: vaultURL) else {
            presentError("""
            Install Claude Code to use this command: https://docs.claude.com/claude-code

            Or choose Wiki → Set Anthropic API Key… to fall back to BYOK.
            """)
            return nil
        }
        AgentWarmer.warmIfNeeded(runner: runner)
        return Session(vaultURL: vaultURL, runner: runner)
    }

    // MARK: - Shared pipeline

    private static func runRecipe(
        kind: OperationKind,
        session: Session,
        controller: WikiOperationController,
        startStatus: String,
        titleFor: (AgentProposal) -> String,
        buildInput: () async throws -> String
    ) async {
        let label = kind.rawValue.capitalized
        DiagnosticLog.log("\(label): start")
        controller.startRecipe(startStatus)
        defer { controller.finishRecipe() }

        do {
            let input = try await buildInput()
            let recipe = try loadRecipe(kind: kind, vaultURL: session.vaultURL)
            let vaultState = buildVaultState(vaultURL: session.vaultURL)
            let prompt = RecipeParser.interpolate(recipe, input: input, vaultState: vaultState)
            DiagnosticLog.log("\(label): calling agent (prompt=\(prompt.count) chars)")

            controller.updateRecipeStatus(
                AgentWarmer.isWarm
                    ? "Asking Claude…"
                    : "Asking Claude (warming cache, first call ~30s)…"
            )

            let model = UserDefaults.standard.string(forKey: "wikiAgentModel")
            let result = try await session.runner.run(prompt: prompt, model: model)
            AgentWarmer.markExercised()
            DiagnosticLog.log("\(label): agent replied \(result.text.count) chars, tokens in=\(result.inputTokens) out=\(result.outputTokens)")

            controller.updateRecipeStatus("Parsing response…")
            let proposal = try AgentResultParser.parseProposal(from: result.text)

            if !proposal.hasChanges {
                DiagnosticLog.log("\(label): noop — \(proposal.rationale)")
                let verdictTitle: String = {
                    switch kind {
                    case .capture: return "Nothing staged"
                    case .chat: return "Answer"
                    case .review: return "No issues found"
                    case .other: return "No action"
                    }
                }()
                let body = proposal.rationale.isEmpty
                    ? "The agent didn't propose any changes."
                    : proposal.rationale
                presentInfo(title: verdictTitle, body: body)
                return
            }

            let op = WikiOperation(
                kind: kind,
                title: titleFor(proposal),
                rationale: proposal.rationale,
                changes: proposal.changes
            )
            do {
                try op.validate()
            } catch let error as WikiOperationError {
                throw AgentError.invalidWikiOperation(String(describing: error))
            }
            DiagnosticLog.log("\(label): staging operation with \(op.changes.count) changes")
            controller.stage(op)
        } catch {
            DiagnosticLog.log("\(label) failed: \(error)")
            presentError("\(label) failed: \(Self.describe(error))")
        }
    }

    // MARK: - Runner resolution

    /// Single CLI runner config for every wiki recipe (Capture/Chat/Review):
    /// cwd=vault, tools=Read/Grep/Glob. Same config means same cache key, so
    /// warming one recipe's cache benefits all three. API fallback doesn't
    /// have tool use — in that mode we rely on the old prompt-side inlining.
    private static func resolveToolEnabledRunner(vaultURL: URL) -> AgentRunner? {
        if let cli = AgentDiscovery.findClaude() {
            return ClaudeCLIAgentRunner(
                binaryURL: cli.url,
                enabledTools: "Read,Grep,Glob",
                workingDirectory: vaultURL
            )
        }
        let keychain = KeychainStore()
        let key = (try? keychain.get(WikiKeychainAccount.anthropicAPIKey)) ?? nil
        if let key, !key.isEmpty {
            return AnthropicAPIAgentRunner()
        }
        return nil
    }

    // MARK: - Recipe loading

    private static func loadRecipe(kind: OperationKind, vaultURL: URL) throws -> Recipe {
        // Bundle always wins for now. Vault-local recipe customization is a
        // future feature — it needs a version field + migration story so
        // shipped recipe updates don't get silently masked by stale copies
        // seeded on older builds. Until that lands we ignore any
        // `.clearly/recipes/*.md` the user has. The files are left in the
        // vault as readable reference; re-enabling vault-first is a one-line
        // flip here.
        _ = vaultURL
        let filename = "\(kind.rawValue).md"
        guard let bundleURL = Bundle.main.url(forResource: "recipes", withExtension: nil)?
            .appendingPathComponent(filename) else {
            throw RecipeError.fileNotFound(path: filename)
        }
        let markdown = try String(contentsOf: bundleURL, encoding: .utf8)
        return try RecipeEngine.loadDefault(markdown)
    }

    // MARK: - Vault state + URL helpers

    /// Pointer used by Capture / Review: the agent now has Read / Grep / Glob
    /// and cwd=vault, so it can read any note on demand. Critically, this
    /// tells it it MUST Read the file before proposing a modify — that's
    /// what previously caused modifyBaseMismatch errors (the agent was
    /// guessing at contents). No more inlining index.md verbatim.
    private static func buildVaultState(vaultURL: URL) -> String {
        let paths = listVaultMarkdownPaths(under: vaultURL)
        var lines = [
            "# Wiki vault",
            "",
            "Your current working directory IS the user's wiki vault. Use your Read / Grep / Glob tools to discover structure and load any notes you need before proposing changes.",
            "",
            "- `Read index.md` — the wiki's current table of contents (load before modifying)",
            "- `Read AGENTS.md` — this vault's conventions and schema",
            "- `Grep <term>` — search every note for a phrase",
            "- `Glob \"**/*.md\"` — list all notes",
            "",
            "**CRITICAL: before proposing any `modify` change, you MUST Read the target file first.** The `before:` field of a modify must be the file's exact current contents. Never guess or reconstruct from memory. If you didn't Read it, don't modify it.",
            "",
            "Quick inventory:",
        ]
        lines.append(contentsOf: paths.map { "- \($0)" })
        return lines.joined(separator: "\n")
    }


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

    nonisolated static func rewriteForContent(_ url: URL) -> URL {
        guard let host = url.host?.lowercased() else { return url }
        if host == "gist.github.com" {
            let parts = url.path
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .split(separator: "/").map(String.init)
            if parts.count == 2,
               let rawURL = URL(string: "https://gist.githubusercontent.com/\(parts[0])/\(parts[1])/raw") {
                return rawURL
            }
        }
        return url
    }

    nonisolated private static func fetchURLContent(_ url: URL) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AgentError.httpError(status: status, body: "fetch failed")
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .isoLatin1) { return text }
        throw AgentError.invalidResponse("non-text response body")
    }

    // MARK: - NSAlert + diagnostics

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

    private static func presentInfo(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .informational
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

    // MARK: - Capture source classification

    /// What the user pasted into the Capture prompt. Auto-detected — URLs
    /// are fetched before being handed to the agent; everything else is
    /// passed through as the source body directly.
    enum CaptureSource: Equatable {
        case empty
        case url(URL)
        case text(String)

        var startStatus: String {
            switch self {
            case .empty: return ""
            case .url(let url): return "Capturing from \(url.host ?? url.absoluteString) — fetching source…"
            case .text: return "Capturing pasted text…"
            }
        }

        var title: String {
            switch self {
            case .empty: return "Capture"
            case .url(let url): return "Capture: \(url.host ?? url.absoluteString)"
            case .text(let body):
                let preview = body
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespaces)
                let truncated = preview.count > 60
                    ? String(preview.prefix(60)) + "…"
                    : preview
                return "Capture: \(truncated)"
            }
        }

        func buildInputBody(maxSourceCharacters: Int) async throws -> String {
            switch self {
            case .empty:
                return ""
            case .url(let url):
                let fetchURL = rewriteForContent(url)
                let body = try await fetchURLContent(fetchURL)
                return """
                URL: \(url.absoluteString)

                Content (truncated if >\(maxSourceCharacters) chars):
                \(body.prefix(maxSourceCharacters))
                """
            case .text(let body):
                let trimmed = body.prefix(maxSourceCharacters)
                return """
                Pasted text (truncated if >\(maxSourceCharacters) chars):
                \(trimmed)
                """
            }
        }
    }

    static func classifySource(_ raw: String) -> CaptureSource {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        // Treat as URL only when the input is a single line and starts with
        // http:// or https://. Everything else is pasted text.
        let isSingleLine = !trimmed.contains("\n")
        if isSingleLine,
           let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           url.host != nil {
            return .url(url)
        }
        return .text(trimmed)
    }

    /// If the clipboard currently holds a plausible URL, return it so the
    /// Capture dialog can pre-fill. Text clipboards are left alone — auto-
    /// pasting a huge chunk of random text into a modal is presumptuous.
    private static func clipboardStringIfLikelySource() -> String? {
        guard let text = NSPasteboard.general.string(forType: .string) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 2000 else { return nil }
        if trimmed.contains("\n") { return nil }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return trimmed
    }

}
