import Foundation

/// What a navigation-away guard should do for a given active document.
public enum NavigationGuardDecision: Equatable {
    /// Doc is clean (or there is no active doc) — proceed without prompting or saving.
    case proceed
    /// File-backed dirty — caller should silently write to disk before navigating.
    case silentSave
    /// Untitled dirty — caller should present a Save / Don't Save / Cancel sheet.
    case promptUser
}

public enum NavigationGuard {
    /// Pure decision: given the active document's state, what should the
    /// caller do before navigating away? Side-effecting save / prompt logic
    /// stays at the platform layer; this function exists so the decision
    /// itself is unit-testable without touching AppKit.
    public static func decide(for doc: OpenDocument?) -> NavigationGuardDecision {
        guard let doc, doc.isDirty else { return .proceed }
        return doc.isUntitled ? .promptUser : .silentSave
    }
}
