import Foundation

final class FindState: ObservableObject {
    @Published var isVisible = false
    @Published var query = ""
    @Published var matchCount = 0
    @Published var currentIndex = 0 // 1-based, 0 = no matches
    @Published var focusRequest = UUID()
    var activeMode: ViewMode = .edit

    var editorNavigateToNext: (() -> Void)?
    var editorNavigateToPrevious: (() -> Void)?
    var previewNavigateToNext: (() -> Void)?
    var previewNavigateToPrevious: (() -> Void)?

    var navigateToNext: (() -> Void)? {
        switch activeMode {
        case .edit:
            editorNavigateToNext
        case .preview:
            previewNavigateToNext
        }
    }

    var navigateToPrevious: (() -> Void)? {
        switch activeMode {
        case .edit:
            editorNavigateToPrevious
        case .preview:
            previewNavigateToPrevious
        }
    }

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            present()
        }
    }

    func present() {
        isVisible = true
        focusRequest = UUID()
    }

    func dismiss() {
        isVisible = false
    }
}
