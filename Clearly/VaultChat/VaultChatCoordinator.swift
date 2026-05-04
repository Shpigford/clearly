import Foundation
import AppKit
import ClearlyCore

/// Drives the vault chat panel. Each user message runs through the chat
/// recipe + the agent runner in a RAG flow — `VaultChatRetriever` selects
/// the most relevant notes, the recipe interpolates them as `{{vault_state}}`,
/// and the agent answers over the inlined context with no tool calls.
@MainActor
enum VaultChatCoordinator {

    // MARK: - Entry points

    /// Toggle the chat panel. Bound to ⌃⌘A and the toolbar/menu Chat button.
    static func startChat(workspace: WorkspaceManager, chat: VaultChatState) {
        if chat.isVisible {
            chat.hide()
            return
        }
        let vaultURL = workspace.activeLocation?.url ?? workspace.locations.first?.url
        guard let vaultURL else {
            presentError("Open a vault to start chatting.")
            return
        }
        chat.bind(to: vaultURL)
        chat.show()
        warmForActiveVaultIfPossible(workspace: workspace)
    }

    /// Send the user's drafted message. Retrieves notes for context, runs
    /// the chat recipe through the agent, appends the assistant reply.
    static func sendChatMessage(
        _ text: String,
        workspace: WorkspaceManager,
        chat: VaultChatState
    ) {
        guard let vaultURL = chat.vaultRoot else {
            presentError("Open a vault to start chatting.")
            return
        }
        let target = vaultURL.standardizedFileURL.resolvingSymlinksInPath().path
        guard let location = workspace.locations.first(where: {
            $0.url.standardizedFileURL.resolvingSymlinksInPath().path == target
        }) else {
            presentError("This vault is no longer registered.")
            return
        }
        guard let runner = resolveCompletionRunner() else {
            presentError("Install Claude Code or Codex CLI to use Chat. https://docs.claude.com/claude-code · https://developers.openai.com/codex/cli")
            return
        }
        guard let vaultIndex = workspace.vaultIndex(for: location) else {
            presentError("Vault index isn't loaded yet — give it a moment and try again.")
            return
        }
        AgentWarmer.warmIfNeeded(runner: runner)

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
                let recipe = try loadChatRecipe()
                guard chat.isCurrent(vaultRoot: vaultURL, contextID: contextID) else { return }

                let hits = try await Task.detached(priority: .userInitiated) {
                    try await VaultChatRetriever.retrieve(
                        question: userMessage.text,
                        vaultURL: vaultURL,
                        index: vaultIndex
                    )
                }.value
                guard chat.isCurrent(vaultRoot: vaultURL, contextID: contextID) else { return }
                DiagnosticLog.log("Chat: retrieved \(hits.count) notes for question (\(userMessage.text.count) chars)")

                let vaultState = VaultChatRetriever.renderContextBlock(hits)
                let transcript = renderTranscript(chat.messages)
                let prompt = RecipeParser.interpolate(recipe, input: transcript, vaultState: vaultState)
                DiagnosticLog.log("Chat: sending (turns=\(chat.messages.count), prompt=\(prompt.count) chars)")

                let result = try await runner.run(prompt: prompt, model: nil)
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
                chat.sendError = describe(error)
            }
        }
    }

    /// Fire a silent cache warmup for the chat path when a vault becomes
    /// active. Bails when no agent CLI is installed. Safe to call repeatedly;
    /// AgentWarmer short-circuits while the cache is still warm.
    static func warmForActiveVaultIfPossible(workspace: WorkspaceManager) {
        guard workspace.activeLocation?.url != nil,
              let runner = resolveCompletionRunner() else {
            return
        }
        AgentWarmer.warmIfNeeded(runner: runner)
    }

    // MARK: - Internal

    private static func renderTranscript(_ messages: [VaultChatMessage]) -> String {
        var lines: [String] = ["Conversation so far:"]
        for message in messages {
            let role = message.role == .user ? "User" : "Assistant"
            lines.append("\(role): \(message.text)")
        }
        lines.append("")
        lines.append("Answer the most recent User message as Assistant, in plain markdown.")
        return lines.joined(separator: "\n")
    }

    private static func loadChatRecipe() throws -> Recipe {
        guard let bundleURL = Bundle.main.url(forResource: "recipes", withExtension: nil)?
            .appendingPathComponent("chat.md") else {
            throw RecipeError.fileNotFound(path: "chat.md")
        }
        let markdown = try String(contentsOf: bundleURL, encoding: .utf8)
        return try RecipeEngine.loadDefault(markdown)
    }

    /// Completion-only runner used by Chat (RAG path). No built-in tools —
    /// the agent's only job is to answer over the inlined retrieved context.
    private static func resolveCompletionRunner() -> AgentRunner? {
        let pref = UserDefaults.standard.string(forKey: "vaultChatRunner") ?? "auto"
        let makeClaude: (AgentDiscovery.CLI) -> AgentRunner = { cli in
            ClaudeCLIAgentRunner(binaryURL: cli.url, enabledTools: "")
        }
        let makeCodex: (AgentDiscovery.CLI) -> AgentRunner = { cli in
            CodexCLIAgentRunner(binaryURL: cli.url)
        }
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

    private static func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Chat"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func describe(_ error: Error) -> String {
        switch error {
        case AgentError.invalidResponse(let m): return "Invalid response: \(m)"
        case AgentError.httpError(let status, _): return "HTTP \(status) fetching the source URL."
        case AgentError.transport(let m): return "Network error: \(m)"
        default: return String(describing: error)
        }
    }
}
