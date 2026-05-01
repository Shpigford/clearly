import Foundation

/// Names every formatting command the host menu / toolbar can dispatch
/// at the active editor. The values are forwarded as strings to the JS
/// bridge in WYSIWYG mode (see `WYSIWYGCommandDispatcher`); in Edit mode
/// they correspond to `ClearlyTextView` selectors picked by the menu's
/// `selector:` argument.
enum FormatCommand: String {
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
    static let wysiwygCommand = Notification.Name("ClearlyWYSIWYGCommand")
}

/// Off-by-default experimental gate for the Tiptap-based editable preview.
/// When enabled, the second toolbar segment (Preview) loads the WYSIWYG
/// editor instead of the static HTML preview, and ⌘B/⌘I/etc. dispatch
/// through the JS bridge.
///
/// Stored in UserDefaults under `wysiwygExperimental`.
enum WYSIWYGExperiment {
    static let userDefaultsKey = "wysiwygExperimental"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: userDefaultsKey)
    }

    static func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: userDefaultsKey)
    }

    /// One-time migration from the previous "Live Preview (Experimental)"
    /// editor engine setting. If the user opted into the CodeMirror live
    /// preview in a prior build, carry that opt-in over to the new Tiptap
    /// editable preview so the feature doesn't silently disappear.
    static func migrateLegacyLivePreviewSettingIfNeeded() {
        let defaults = UserDefaults.standard
        // Don't override an explicit choice on the new key.
        guard defaults.object(forKey: userDefaultsKey) == nil else {
            defaults.removeObject(forKey: "editorEngine")
            return
        }
        if defaults.string(forKey: "editorEngine") == "livePreviewExperimental" {
            defaults.set(true, forKey: userDefaultsKey)
        }
        defaults.removeObject(forKey: "editorEngine")
    }
}

enum WYSIWYGCommandDispatcher {
    /// True when the editable-preview experiment is enabled AND the active
    /// document is currently displayed in WYSIWYG view mode. Used by the
    /// formatting toolbar / menu items to decide whether ⌘B/⌘I/etc. should
    /// route into the Tiptap bridge instead of the AppKit NSTextView.
    @MainActor
    static var isActive: Bool {
        guard WYSIWYGExperiment.isEnabled else { return false }
        return WorkspaceManager.shared.currentViewMode == .wysiwyg
    }

    static func send(_ command: FormatCommand) {
        NotificationCenter.default.post(
            name: .wysiwygCommand,
            object: nil,
            userInfo: ["command": command.rawValue]
        )
    }
}
