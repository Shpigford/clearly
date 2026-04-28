import SwiftUI
import ClearlyCore

/// The full-screen diff-review sheet. Presented from `MacDetailColumn` when
/// the `WikiOperationController` has a staged operation. The user reviews
/// the agent's proposed multi-file changes here; nothing lands on disk until
/// they hit Accept.
struct WikiDiffSheet: View {
    @Bindable var controller: WikiOperationController
    let onApplied: (WikiOperation, URL) -> Void

    var body: some View {
        if let op = controller.stagedOperation {
            content(for: op)
                .frame(minWidth: 800, minHeight: 560)
        }
    }

    @ViewBuilder
    private func content(for op: WikiOperation) -> some View {
        VStack(spacing: 0) {
            header(op)
            Divider()
            WikiDiffView(controller: controller, operation: op)
                .layoutPriority(1)
            Divider()
            footer(op)
        }
    }

    // MARK: - Header

    private func header(_ op: WikiOperation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(op.kind.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(op.title)
                    .font(.headline)
                Spacer()
                Text(summaryLine(for: op))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !op.rationale.isEmpty {
                Text(op.rationale)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Footer

    private func footer(_ op: WikiOperation) -> some View {
        HStack(spacing: 12) {
            if let error = controller.applyError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(keepStatus(for: op))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Reject") {
                controller.dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(controller.isApplying)

            Button("Accept") {
                controller.accept(onApplied: onApplied)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(controller.isApplying || controller.effectiveChanges.isEmpty || controller.stagedVaultRoot == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Summaries

    private func summaryLine(for op: WikiOperation) -> String {
        var creates = 0, modifies = 0, deletes = 0
        for c in op.changes {
            switch c {
            case .create: creates += 1
            case .modify: modifies += 1
            case .delete: deletes += 1
            }
        }
        var parts: [String] = []
        if creates > 0 { parts.append("\(creates) new") }
        if modifies > 0 { parts.append("\(modifies) edited") }
        if deletes > 0 { parts.append("\(deletes) deleted") }
        return parts.joined(separator: " · ")
    }

    private func keepStatus(for op: WikiOperation) -> String {
        let total = op.changes.count
        let kept = total - controller.rejectedPaths.count
        if controller.rejectedPaths.isEmpty { return "\(total) file\(total == 1 ? "" : "s") to apply" }
        return "\(kept) of \(total) file\(total == 1 ? "" : "s") kept"
    }
}

private extension OperationKind {
    var displayName: String {
        switch self {
        case .capture: return "Capture"
        case .chat: return "Chat"
        case .review: return "Review"
        case .integrate: return "Integrate"
        case .other: return "Operation"
        }
    }
}
