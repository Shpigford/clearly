import Foundation

/// State for the wiki chat panel. Multi-turn conversation against the current
/// vault — each user turn runs through the query recipe + the agent runner,
/// with the prior turn history inlined into the prompt so Claude sees context.
/// Chat is ephemeral per window (not persisted across launches in V1).
@Observable
@MainActor
final class WikiChatState {
    var messages: [WikiChatMessage] = []
    var draft: String = ""
    var isSending: Bool = false
    var sendError: String?
    var isVisible: Bool = false

    func toggle() { isVisible.toggle() }
    func show() { isVisible = true }
    func hide() { isVisible = false }

    func reset() {
        messages.removeAll()
        draft = ""
        sendError = nil
        isSending = false
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
