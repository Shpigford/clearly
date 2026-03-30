import Foundation

final class FindState: ObservableObject {
    @Published var isVisible = false
    @Published var query = ""
    @Published var matchCount = 0
    @Published var currentIndex = 0 // 1-based, 0 = no matches
    @Published var focusRequest = UUID()

    // Set by EditorView coordinator, called by FindBarView
    var navigateToNext: (() -> Void)?
    var navigateToPrevious: (() -> Void)?

    func present() {
        isVisible = true
        focusRequest = UUID()
    }
}
