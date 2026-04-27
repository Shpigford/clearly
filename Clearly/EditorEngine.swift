import Foundation

enum EditorEngine: String, CaseIterable, Identifiable {
    case classic
    case livePreviewExperimental

    var id: String { rawValue }

    static var current: EditorEngine {
        resolved(rawValue: UserDefaults.standard.string(forKey: "editorEngine") ?? "")
    }

    static var availableCases: [EditorEngine] {
        EditorEngine.allCases
    }

    static func resolved(rawValue: String) -> EditorEngine {
        EditorEngine(rawValue: rawValue) ?? .classic
    }

    var displayName: String {
        switch self {
        case .classic:
            return "Classic"
        case .livePreviewExperimental:
            return "Live Preview (Experimental)"
        }
    }

    var showsSeparatePreview: Bool {
        self == .classic
    }

    var isAvailable: Bool {
        true
    }
}

enum LiveEditorCommand: String {
    case bold
    case italic
    case strikethrough
    case heading
    case link
    case image
    case bulletList
    case numberedList
    case todoList
    case blockquote
    case horizontalRule
    case table
    case inlineCode
    case codeBlock
    case inlineMath
    case mathBlock
    case pageBreak
}

extension Notification.Name {
    static let liveEditorCommand = Notification.Name("ClearlyLiveEditorCommand")
}

enum LiveEditorCommandDispatcher {
    static var isActive: Bool {
        EditorEngine.current == .livePreviewExperimental
    }

    static func send(_ command: LiveEditorCommand) {
        NotificationCenter.default.post(
            name: .liveEditorCommand,
            object: nil,
            userInfo: ["command": command.rawValue]
        )
    }
}
