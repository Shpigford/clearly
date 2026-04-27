import SwiftUI
import ClearlyCore

// MARK: - Notification names
//
// These notifications connect the editor, preview, and QuickSwitcher across
// the app. Defined here rather than co-located with any specific view so
// they survive shell rewrites.
extension Notification.Name {
    static let scrollEditorToLine = Notification.Name("scrollEditorToLine")
    static let scrollPreviewToLine = Notification.Name("scrollPreviewToLine")
    static let flushEditorBuffer = Notification.Name("flushEditorBuffer")
    static let navigateWikiLink = Notification.Name("navigateWikiLink")
    static let highlightTextInEditor = Notification.Name("highlightTextInEditor")
    static let highlightTextInPreview = Notification.Name("highlightTextInPreview")

    // Wiki (LLM) commands — published by Wiki menu items and observed by the
    // WikiAgentCoordinator.
    static let wikiCapture = Notification.Name("wikiCapture")
    static let wikiChat = Notification.Name("wikiChat")
    static let wikiToggleLogSidebar = Notification.Name("wikiToggleLogSidebar")
}

// MARK: - Focused values
//
// Menu commands read these via `@FocusedValue` to act on the active window
// without needing a direct reference. `FocusedValuesModifier` is applied to
// `MacDetailColumn` so every value is scoped to the real document chrome.

struct ViewModeKey: FocusedValueKey {
    typealias Value = Binding<ViewMode>
}

struct DocumentTextKey: FocusedValueKey {
    typealias Value = String
}

struct DocumentFileURLKey: FocusedValueKey {
    typealias Value = URL
}

struct FindStateKey: FocusedValueKey {
    typealias Value = FindState
}

struct OutlineStateKey: FocusedValueKey {
    typealias Value = OutlineState
}

struct BacklinksStateKey: FocusedValueKey {
    typealias Value = BacklinksState
}

struct JumpToLineStateKey: FocusedValueKey {
    typealias Value = JumpToLineState
}

struct ActiveVaultIsWikiKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var viewMode: Binding<ViewMode>? {
        get { self[ViewModeKey.self] }
        set { self[ViewModeKey.self] = newValue }
    }
    var documentText: String? {
        get { self[DocumentTextKey.self] }
        set { self[DocumentTextKey.self] = newValue }
    }
    var documentFileURL: URL? {
        get { self[DocumentFileURLKey.self] }
        set { self[DocumentFileURLKey.self] = newValue }
    }
    var findState: FindState? {
        get { self[FindStateKey.self] }
        set { self[FindStateKey.self] = newValue }
    }
    var outlineState: OutlineState? {
        get { self[OutlineStateKey.self] }
        set { self[OutlineStateKey.self] = newValue }
    }
    var backlinksState: BacklinksState? {
        get { self[BacklinksStateKey.self] }
        set { self[BacklinksStateKey.self] = newValue }
    }
    var jumpToLineState: JumpToLineState? {
        get { self[JumpToLineStateKey.self] }
        set { self[JumpToLineStateKey.self] = newValue }
    }
    var activeVaultIsWiki: Bool? {
        get { self[ActiveVaultIsWikiKey.self] }
        set { self[ActiveVaultIsWikiKey.self] = newValue }
    }
}

struct FocusedValuesModifier: ViewModifier {
    @Bindable var workspace: WorkspaceManager
    var findState: FindState
    var outlineState: OutlineState
    var backlinksState: BacklinksState
    var jumpToLineState: JumpToLineState

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.viewMode, $workspace.currentViewMode)
            .focusedSceneValue(\.documentText, workspace.currentFileText)
            .focusedSceneValue(\.documentFileURL, workspace.currentFileURL)
            .focusedSceneValue(\.findState, findState)
            .focusedSceneValue(\.outlineState, outlineState)
            .focusedSceneValue(\.backlinksState, backlinksState)
            .focusedSceneValue(\.jumpToLineState, jumpToLineState)
            .focusedSceneValue(\.activeVaultIsWiki, workspace.activeVaultIsWiki)
    }
}
