import Foundation

public final class FindState: ObservableObject {
    public init() {}

    @Published public var isVisible = false
    @Published public var query = ""
    @Published public var matchCount = 0
    @Published public var currentIndex = 0 // 1-based, 0 = no matches
    @Published public var focusRequest = UUID()
    public var activeMode: ViewMode = .edit

    public var editorNavigateToNext: (() -> Void)?
    public var editorNavigateToPrevious: (() -> Void)?
    public var previewNavigateToNext: (() -> Void)?
    public var previewNavigateToPrevious: (() -> Void)?

    public var navigateToNext: (() -> Void)? {
        switch activeMode {
        case .edit:
            editorNavigateToNext
        case .preview:
            previewNavigateToNext
        }
    }

    public var navigateToPrevious: (() -> Void)? {
        switch activeMode {
        case .edit:
            editorNavigateToPrevious
        case .preview:
            previewNavigateToPrevious
        }
    }

    public func toggle() {
        if isVisible {
            dismiss()
        } else {
            present()
        }
    }

    public func present() {
        isVisible = true
        focusRequest = UUID()
    }

    public func dismiss() {
        isVisible = false
    }
}
