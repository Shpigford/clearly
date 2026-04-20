import Foundation

public final class JumpToLineState: ObservableObject {
    public init() {}

    @Published public var isVisible = false
    @Published public var lineText = ""
    @Published public var focusRequest = UUID()
    public var totalLines: Int = 1
    public var onJump: ((Int) -> Void)?
    public var editorLineInfo: (() -> (current: Int, total: Int))?

    public func toggle() {
        if isVisible {
            dismiss()
        } else {
            present()
        }
    }

    public func present() {
        if let info = editorLineInfo?() {
            totalLines = info.total
            lineText = "\(info.current)"
        }
        isVisible = true
        focusRequest = UUID()
    }

    public func dismiss() {
        isVisible = false
    }

    public func commit() {
        guard let line = Int(lineText), line >= 1 else { return }
        onJump?(min(line, totalLines))
        dismiss()
    }
}
