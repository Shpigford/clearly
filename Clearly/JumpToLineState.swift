import Foundation

final class JumpToLineState: ObservableObject {
    @Published var isVisible = false
    @Published var lineText = ""
    @Published var focusRequest = UUID()
    var totalLines: Int = 1
    var onJump: ((Int) -> Void)?
    var editorLineInfo: (() -> (current: Int, total: Int))?

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            present()
        }
    }

    func present() {
        if let info = editorLineInfo?() {
            totalLines = info.total
            lineText = "\(info.current)"
        }
        isVisible = true
        focusRequest = UUID()
    }

    func dismiss() {
        isVisible = false
    }

    func commit() {
        guard let line = Int(lineText), line >= 1 else { return }
        onJump?(min(line, totalLines))
        dismiss()
    }
}
