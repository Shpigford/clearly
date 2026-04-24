import SwiftUI
import ClearlyCore

/// Multi-file diff renderer used inside the wiki diff-review sheet. Two-pane
/// layout: a file list on the left (with per-file reject toggles), a
/// side-by-side unified diff for the selected file on the right. Reuses
/// `LineDiff` for line-level alignment — no external dependency.
struct WikiDiffView: View {
    @Bindable var controller: WikiOperationController
    let operation: WikiOperation

    var body: some View {
        HSplitView {
            fileList
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
            diffPane
                .frame(minWidth: 480)
        }
    }

    // MARK: - File list

    private var fileList: some View {
        List(selection: Binding(
            get: { controller.selectedPath },
            set: { controller.selectedPath = $0 }
        )) {
            ForEach(operation.changes, id: \.path) { change in
                WikiDiffFileRow(
                    change: change,
                    isRejected: controller.isRejected(change.path),
                    onToggleReject: { controller.toggleReject(path: change.path) }
                )
                .tag(change.path)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Diff pane

    @ViewBuilder
    private var diffPane: some View {
        if let path = controller.selectedPath,
           let change = operation.changes.first(where: { $0.path == path }) {
            WikiDiffDetail(change: change)
                .id(path)
        } else {
            ContentUnavailableView(
                "No file selected",
                systemImage: "doc.text",
                description: Text("Select a file on the left to see its changes.")
            )
        }
    }
}

// MARK: - File row

private struct WikiDiffFileRow: View {
    let change: FileChange
    let isRejected: Bool
    let onToggleReject: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 16)
            Text(change.path)
                .lineLimit(1)
                .truncationMode(.middle)
                .strikethrough(isRejected)
                .foregroundStyle(isRejected ? .secondary : .primary)
            Spacer(minLength: 4)
            Button {
                onToggleReject()
            } label: {
                Image(systemName: isRejected ? "arrow.uturn.backward.circle" : "xmark.circle")
                    .foregroundStyle(isRejected ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(isRejected ? "Include this file" : "Skip this file")
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        switch change {
        case .create: return "plus.square"
        case .modify: return "pencil"
        case .delete: return "minus.square"
        }
    }

    private var iconColor: Color {
        switch change {
        case .create: return .green
        case .modify: return .blue
        case .delete: return .red
        }
    }
}

// MARK: - Diff detail (one file)

private struct WikiDiffDetail: View {
    let change: FileChange

    var body: some View {
        switch change {
        case .create(_, let contents):
            fullFile(title: "New file", text: contents, tint: .green)
        case .delete(_, let contents):
            fullFile(title: "Deleted file", text: contents, tint: .red)
        case .modify(_, let before, let after):
            ModifyDiff(before: before, after: after)
        }
    }

    private func fullFile(title: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            ScrollView {
                Text(text.isEmpty ? " " : text)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(tint.opacity(0.12))
            }
        }
    }
}

// MARK: - Modify diff

private struct ModifyDiff: View {
    let before: String
    let after: String

    @State private var rows: [LineDiff.Row] = []
    @State private var isTooLarge = false
    @State private var didCompute = false

    var body: some View {
        Group {
            if !didCompute {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isTooLarge {
                ContentUnavailableView(
                    "Too large to diff",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Open this note after accepting to inspect it directly.")
                )
            } else {
                diffContent
            }
        }
        .task(id: before + "\0" + after) { computeDiff() }
    }

    private func computeDiff() {
        do {
            rows = try LineDiff.rows(left: before, right: after)
            isTooLarge = false
        } catch {
            rows = []
            isTooLarge = true
        }
        didCompute = true
    }

    private var diffContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                header("Before")
                header("After")
            }
            Divider()
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        HStack(alignment: .top, spacing: 1) {
                            cell(text: row.left, op: row.op, side: .left)
                            cell(text: row.right, op: row.op, side: .right)
                        }
                    }
                }
            }
        }
    }

    private enum Side { case left, right }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    private func cell(text: String?, op: LineDiff.Op, side: Side) -> some View {
        let background: Color = {
            switch (op, side) {
            case (.removed, .left): return .red.opacity(0.18)
            case (.added, .right): return .green.opacity(0.18)
            default: return .clear
            }
        }()
        return Text(text ?? " ")
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(background)
    }
}
