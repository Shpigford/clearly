import Foundation

/// State for the vault chat panel. Multi-turn conversation against a chosen
/// vault — each user turn runs through the chat recipe + the agent runner,
/// with the prior turn history inlined into the prompt so the model sees
/// context. Chat is ephemeral per window (not persisted across launches).
///
/// Two paths can change which vault chat targets:
///
/// - `bind(to:)` is the system path. Called when the panel opens or when the
///   active vault changes in the sidebar. It auto-rebinds chat to whatever
///   vault is currently active. **No-op when `isPinned` is true** — pinning
///   is the user's explicit intent to keep chatting with a specific vault
///   regardless of sidebar focus.
/// - `pin(to:)` is the picker path. Called when the user picks a vault from
///   the chat panel header dropdown. Switches chat to the picked vault, clears
///   history, and sets the pin so subsequent active-vault changes don't
///   silently rebind.
///
/// Closing the panel clears the pin so the next open defaults back to the
/// active vault.
@Observable
@MainActor
final class WikiChatState {
    private(set) var vaultRoot: URL?
    private(set) var isPinned: Bool = false
    var contextID = UUID()
    var messages: [WikiChatMessage] = []
    var draft: String = ""
    var isSending: Bool = false
    var sendError: String?
    var isVisible: Bool = false

    func toggle() { isVisible.toggle() }
    func show() { isVisible = true }
    func hide() {
        isVisible = false
        isPinned = false
    }

    func reset(vaultRoot: URL? = nil) {
        self.vaultRoot = vaultRoot
        contextID = UUID()
        messages.removeAll()
        draft = ""
        sendError = nil
        isSending = false
    }

    /// Auto-bind path used by `WikiAgentCoordinator.startChat` and active-vault
    /// change notifications. Skipped while the user has a pinned selection so
    /// switching sidebar focus doesn't silently change chat's target.
    func bind(to vaultRoot: URL) {
        if isPinned { return }
        guard let currentRoot = self.vaultRoot else {
            self.vaultRoot = vaultRoot
            return
        }
        if !Self.sameFileURL(currentRoot, vaultRoot) {
            reset(vaultRoot: vaultRoot)
        }
    }

    /// Explicit picker selection. Switches chat to the picked vault, clears
    /// history, and pins until the panel closes. Idempotent when the picked
    /// vault matches the current target.
    func pin(to vaultRoot: URL) {
        if let currentRoot = self.vaultRoot, Self.sameFileURL(currentRoot, vaultRoot) {
            isPinned = true
            return
        }
        reset(vaultRoot: vaultRoot)
        isPinned = true
    }

    func isCurrent(vaultRoot: URL, contextID: UUID) -> Bool {
        guard let currentRoot = self.vaultRoot else { return false }
        return self.contextID == contextID && Self.sameFileURL(currentRoot, vaultRoot)
    }

    func appendUser(_ text: String) -> WikiChatMessage {
        let message = WikiChatMessage(role: .user, text: text)
        messages.append(message)
        return message
    }

    func appendAssistant(_ text: String) -> WikiChatMessage {
        let message = WikiChatMessage(role: .assistant, text: text)
        messages.append(message)
        return message
    }

    private static func sameFileURL(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path ==
            rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

struct WikiChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: Role
    let text: String
    let timestamp: Date

    enum Role { case user, assistant }

    init(id: UUID = UUID(), role: Role, text: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}
