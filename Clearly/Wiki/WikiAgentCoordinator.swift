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

    /// Entry point for ⌃⌘A, the Wiki menu, and the toolbar Chat button.
    /// Toggles the chat panel — repeated invocations close it.
    static func startChat(workspace: WorkspaceManager, chat: WikiChatState) {
        if chat.isVisible {
            chat.hide()
            return
        }
        guard let vaultURL = workspace.activeLocation?.url, workspace.activeVaultIsWiki else {
            presentError("Chat is only available when the active note lives in a wiki vault.")
            return
        }
        chat.bind(to: vaultURL)
        chat.show()
    }

    /// Called by WikiChatView when the user submits a message. RAG flow:
    /// retrieve the most-relevant notes for the latest user message in process
    /// (semantic search via `WikiChatRetriever`), splice them into the prompt
    /// as `{{vault_state}}`, and ask the LLM to answer over the inlined
    /// context — no agent tool calls, no MCP subprocess.
    static func sendChatMessage(
        _ text: String,
        workspace: WorkspaceManager,
        chat: WikiChatState
    ) {
        guard let location = workspace.activeLocation,
              let vaultURL = workspace.activeLocation?.url,
              workspace.activeVaultIsWiki else {
            presentError("Chat is only available when the active note lives in a wiki vault.")
            return
        }
        guard let runner = resolveCompletionRunner() else {
            presentError("Install Claude Code or Codex CLI to use Wiki Chat. https://docs.claude.com/claude-code · https://developers.openai.com/codex/cli")
            return
        }
        guard let vaultIndex = workspace.vaultIndex(for: location) else {
            presentError("Vault index isn't loaded yet — give it a moment and try again.")
            return
        }
        AgentWarmer.warmIfNeeded(runner: runner)

        chat.bind(to: vaultURL)
        let userMessage = chat.appendUser(text)
        chat.draft = ""
        chat.isSending = true
        chat.sendError = nil
        let contextID = chat.contextID

        Task { @MainActor in
            defer {
                if chat.isCurrent(vaultRoot: vaultURL, contextID: contextID) {
                    chat.isSending = false
                }
            }
            do {
                let recipe = try loadRecipe(kind: .chat, vaultURL: vaultURL)
                guard chat.isCurrent(vaultRoot: vaultURL, contextID: contextID) else { return }

                let hits = try await Task.detached(priority: .userInitiated) {
                    try await WikiChatRetriever.retrieve(
                        question: userMessage.text,
                        vaultURL: vaultURL,
                        index: vaultIndex
                    )
                }.value
                guard chat.isCurrent(vaultRoot: vaultURL, contextID: contextID) else { return }
                DiagnosticLog.log("Chat: retrieved \(hits.count) notes for question (\(userMessage.text.count) chars)")

                let vaultState = WikiChatRetriever.renderContextBlock(hits)
                let transcript = Self.renderTranscript(chat.messages)
                let prompt = RecipeParser.interpolate(recipe, input: transcript, vaultState: vaultState)
                DiagnosticLog.log("Chat: sending (turns=\(chat.messages.count), prompt=\(prompt.count) chars)")

                let model = UserDefaults.standard.string(forKey: "wikiAgentModel")
                let result = try await runner.run(prompt: prompt, model: model)
                AgentWarmer.markExercised()
                DiagnosticLog.log("Chat: reply \(result.text.count) chars, tokens in=\(result.inputTokens) out=\(result.outputTokens)")

                let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard chat.isCurrent(vaultRoot: vaultURL, contextID: contextID) else { return }
                guard !trimmed.isEmpty else {
                    chat.sendError = "Empty response from the agent."
                    return
                }
                _ = chat.appendAssistant(trimmed)
            } catch {
                DiagnosticLog.log("Chat failed: \(error)")
                guard chat.isCurrent(vaultRoot: vaultURL, contextID: contextID) else { return }
                chat.sendError = Self.describe(error)
            }
        }
    }

    /// Serialise the conversation into the form the chat recipe expects as
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

    /// Auto-Review entry point. Fires on vault open if it's been ≥24h since
    /// the last successful run. Unscoped (general pass) — no focus prompt.
    /// Results park on `controller.pendingOperation` so the diff sheet
    /// doesn't pop unprompted; the LogSidebar badge invites the user to
    /// review when ready. Idempotent (state-file-gated) and silent on
    /// "no claude CLI" — never popping an alert at vault-open time.
    static func runReviewIfStale(workspace: WorkspaceManager, controller: WikiOperationController) {
        guard workspace.activeVaultIsWiki,
              let vaultURL = workspace.activeLocation?.url else {
            return
        }

        if let state = WikiVaultState.read(at: vaultURL),
           let last = state.lastReviewAt {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < 24 * 3600 {
                let minutes = Int(elapsed / 60)
                DiagnosticLog.log("[Review] skipped: ran \(minutes)m ago")
                return
            }
        }

        // Already running or pending? Don't double-fire.
        guard !controller.hasPendingReview,
              !controller.isPresenting,
              !controller.isRunningRecipe,
              !controller.isAutoReviewing else {
            return
        }

        guard let runner = resolveToolEnabledRunner(vaultURL: vaultURL) else {
            DiagnosticLog.log("[Review] skipped: no agent CLI installed")
            return
        }
        AgentWarmer.warmIfNeeded(runner: runner)
        let session = Session(vaultURL: vaultURL, runner: runner)

        Task { @MainActor in
            // Re-check on the @MainActor before doing real work. Two
            // synchronous callers (`.onAppear` + `.onChange`) can both pass
            // the synchronous guards above before either Task body runs;
            // `runRecipe` sets `isAutoReviewing` synchronously at its top
            // (for `.holdForReview` mode), so the second Task to start sees
            // the flag and bails.
            guard !controller.isAutoReviewing else {
                DiagnosticLog.log("[Review] skipped: another auto-Review in flight")
                return
            }
            await runRecipe(
                kind: .review,
                session: session,
                controller: controller,
                startStatus: "Reviewing the wiki…",
                titleFor: { proposal in
                    let count = proposal.changes.count
                    return count == 0
                        ? "Review: no issues"
                        : "Review: \(count) fix\(count == 1 ? "" : "es")"
                },
                stageMode: .holdForReview
            ) { "" }
        }
    }

    /// Fire a silent cache warmup for the chat/query path as soon as a wiki
    /// vault becomes active. Bails when no agent CLI is installed (or the
    /// user picked one that isn't present). Safe to call repeatedly;
    /// AgentWarmer short-circuits while the cache is still warm.
    static func warmForActiveVaultIfPossible(workspace: WorkspaceManager) {
        guard workspace.activeVaultIsWiki,
              let vaultURL = workspace.activeLocation?.url,
              let runner = resolveToolEnabledRunner(vaultURL: vaultURL) else {
            return
        }
        AgentWarmer.warmIfNeeded(runner: runner)
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
            presentError("Install Claude Code or Codex CLI to use this command. https://docs.claude.com/claude-code · https://developers.openai.com/codex/cli")
            return nil
        }
        AgentWarmer.warmIfNeeded(runner: runner)
        return Session(vaultURL: vaultURL, runner: runner)
    }

    // MARK: - Shared pipeline

    /// Where a successful proposal lands. `.immediate` opens the diff sheet
    /// straight away (Capture/Chat use this); `.holdForReview` parks the
    /// proposal on `pendingOperation` so the auto-Review path can surface a
    /// badge instead.
    enum StageMode {
        case immediate
        case holdForReview
    }

    private static func runRecipe(
        kind: OperationKind,
        session: Session,
        controller: WikiOperationController,
        startStatus: String,
        titleFor: (AgentProposal) -> String,
        stageMode: StageMode = .immediate,
        buildInput: () async throws -> String
    ) async {
        let label = kind.rawValue.capitalized
        DiagnosticLog.log("\(label): start")
        switch stageMode {
        case .immediate:
            controller.startRecipe(startStatus)
        case .holdForReview:
            controller.isAutoReviewing = true
        }
        defer {
            switch stageMode {
            case .immediate:
                controller.finishRecipe()
            case .holdForReview:
                controller.isAutoReviewing = false
            }
        }

        do {
            let input = try await buildInput()
            let recipe = try loadRecipe(kind: kind, vaultURL: session.vaultURL)
            let vaultState = buildVaultState(vaultURL: session.vaultURL)
            let prompt = RecipeParser.interpolate(recipe, input: input, vaultState: vaultState)
            DiagnosticLog.log("\(label): calling agent (prompt=\(prompt.count) chars)")

            if stageMode == .immediate {
                controller.updateRecipeStatus(
                    AgentWarmer.isWarm
                        ? "Asking the agent…"
                        : "Asking the agent (warming cache, first call may take a minute)…"
                )
            }

            let model = UserDefaults.standard.string(forKey: "wikiAgentModel")
            let result = try await session.runner.run(prompt: prompt, model: model)
            AgentWarmer.markExercised()
            DiagnosticLog.log("\(label): agent replied \(result.text.count) chars, tokens in=\(result.inputTokens) out=\(result.outputTokens)")

            if stageMode == .immediate {
                controller.updateRecipeStatus("Parsing response…")
            }
            let proposal = try AgentResultParser.parseProposal(from: result.text)

            if !proposal.hasChanges {
                DiagnosticLog.log("\(label): noop — \(proposal.rationale)")
                if kind == .review {
                    // Successful Review with nothing to do still resets the
                    // 24h cooldown — otherwise a clean wiki re-fires Review
                    // every launch.
                    WikiVaultState.recordReviewRun(at: session.vaultURL)
                }
                if stageMode == .holdForReview { return }
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
            switch stageMode {
            case .immediate:
                DiagnosticLog.log("\(label): staging operation with \(op.changes.count) changes")
                controller.stage(op, vaultRoot: session.vaultURL)
            case .holdForReview:
                DiagnosticLog.log("\(label): holding operation with \(op.changes.count) changes for review")
                controller.holdForReview(op, vaultRoot: session.vaultURL)
            }
        } catch {
            DiagnosticLog.log("\(label) failed: \(error)")
            if stageMode == .immediate {
                presentError("\(label) failed: \(Self.describe(error))")
            }
        }
    }

    // MARK: - Runner resolution

    /// Tool-enabled runner used by Capture and Review: cwd=vault, built-in
    /// Read/Grep/Glob enabled so the agent can explore on demand. Honors
    /// the `wikiAgentRunner` user preference (`auto | claude | codex`).
    /// Auto prefers Claude when both are installed; falls back to Codex;
    /// returns nil if neither resolves.
    private static func resolveToolEnabledRunner(vaultURL: URL) -> AgentRunner? {
        resolveRunner { cli in
            ClaudeCLIAgentRunner(
                binaryURL: cli.url,
                enabledTools: "Read,Grep,Glob",
                workingDirectory: vaultURL
            )
        } codex: { cli in
            CodexCLIAgentRunner(
                binaryURL: cli.url,
                workingDirectory: vaultURL
            )
        }
    }

    /// Completion-only runner used by Chat (RAG path). No built-in tools —
    /// the agent's only job is to answer over the inlined retrieved
    /// context. cwd=stable scratch dir for prompt-cache reuse.
    private static func resolveCompletionRunner() -> AgentRunner? {
        resolveRunner { cli in
            ClaudeCLIAgentRunner(
                binaryURL: cli.url,
                enabledTools: ""
            )
        } codex: { cli in
            CodexCLIAgentRunner(binaryURL: cli.url)
        }
    }

    private static func resolveRunner(
        claude makeClaude: (AgentDiscovery.CLI) -> AgentRunner,
        codex makeCodex: (AgentDiscovery.CLI) -> AgentRunner
    ) -> AgentRunner? {
        let pref = UserDefaults.standard.string(forKey: "wikiAgentRunner") ?? "auto"
        switch pref {
        case "claude":
            return AgentDiscovery.findClaude().map(makeClaude)
        case "codex":
            return AgentDiscovery.findCodex().map(makeCodex)
        default:
            if let claude = AgentDiscovery.findClaude() {
                return makeClaude(claude)
            }
            return AgentDiscovery.findCodex().map(makeCodex)
        }
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
        case AgentError.invalidResponse(let m): return "Invalid response: \(m)"
        case AgentError.httpError(let status, _): return "HTTP \(status) fetching the source URL."
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
