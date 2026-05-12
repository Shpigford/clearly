import SwiftUI

@MainActor
@Observable
final class ScratchpadDeleteUndoController {
    var pendingToken: ScratchpadDeleteToken?
    var pendingTitle: String = ""
    private var dismissWork: DispatchWorkItem?
    private var restoreAction: (() -> Void)?
    private let timeoutSeconds: TimeInterval = 10

    func present(token: ScratchpadDeleteToken, onRestore: @escaping () -> Void) {
        dismissWork?.cancel()
        pendingToken = token
        pendingTitle = token.title
        restoreAction = onRestore
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.expire() }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeoutSeconds, execute: work)
    }

    func restore() {
        guard pendingToken != nil else { return }
        restoreAction?()
        clear()
    }

    func dismiss() {
        clear()
    }

    private func expire() {
        clear()
    }

    private func clear() {
        dismissWork?.cancel()
        dismissWork = nil
        pendingToken = nil
        pendingTitle = ""
        restoreAction = nil
    }
}

struct ScratchpadDeleteUndoToast: View {
    @Environment(ScratchpadDeleteUndoController.self) private var controller

    var body: some View {
        if controller.pendingToken != nil {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
                Text("Deleted \(displayTitle)")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button("Undo") { controller.restore() }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("z", modifiers: .command)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.separator.opacity(0.4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var displayTitle: String {
        let title = controller.pendingTitle
        if title.isEmpty || title == ScratchpadNote.titlePlaceholder { return "scratchpad" }
        return "“\(String(title.prefix(40)))”"
    }
}
