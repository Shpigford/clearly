import Foundation

public final class FindState: ObservableObject {
    public init() {}

    @Published public var isVisible = false
    @Published public var query = ""
    @Published public var matchCount = 0
    @Published public var currentIndex = 0 // 1-based, 0 = no matches
    @Published public var resultsAreStale = false
    @Published public var focusRequest = UUID()
    @Published public var replaceFocusRequest = UUID()
    public var activeMode: ViewMode = .edit

    @Published public var replacementText = ""
    @Published public var showReplace = false
    @Published public var caseSensitive = false
    @Published public var useRegex = false
    @Published public var regexError: String?
    @Published public var lastReplaceCount: Int?

    public var editorNavigateToNext: (() -> Void)?
    public var editorNavigateToPrevious: (() -> Void)?
    public var previewNavigateToNext: (() -> Void)?
    public var previewNavigateToPrevious: (() -> Void)?
    public var editorPerformReplace: (() -> Void)?
    public var editorPerformReplaceAll: (() -> Void)?

    public var canNavigate: Bool {
        !query.isEmpty && (activeMode == .preview || regexError == nil) && (resultsAreStale || matchCount > 0)
    }

    public var canReplace: Bool {
        activeMode == .edit && regexError == nil && !query.isEmpty && matchCount > 0
    }

    public var canReplaceAll: Bool {
        activeMode == .edit && regexError == nil && !query.isEmpty && matchCount > 0
    }

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
        lastReplaceCount = nil
    }
}
