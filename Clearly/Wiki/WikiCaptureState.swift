import Foundation

/// Drives the Capture sheet — a modal SwiftUI input surface for the
/// `Wiki → Capture` command. Replaces the earlier NSAlert prompt.
@Observable
@MainActor
final class WikiCaptureState {
    var isVisible: Bool = false
    var draft: String = ""

    func show(prefill: String? = nil) {
        draft = prefill ?? ""
        isVisible = true
    }

    func dismiss() {
        isVisible = false
        draft = ""
    }
}
