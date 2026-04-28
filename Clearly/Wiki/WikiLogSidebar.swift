import SwiftUI
import ClearlyCore

/// Trailing-edge panel that renders `log.md` as a scrubbable timeline of
/// accepted operations. Each entry is expandable to show the rationale and
/// the list of file changes that landed. Click a change row to open that
/// file in the editor.
struct WikiLogSidebar: View {
    @Bindable var state: WikiLogState
    @Bindable var controller: WikiOperationController
    let vaultRoot: URL?
    let openPath: (String) -> Void
    let openLog: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            separator
            if controller.hasPendingOperation {
                pendingBadge
                separator
            }
            content
        }
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 380, maxHeight: .infinity, alignment: .top)
        .background(Theme.outlinePanelBackgroundSwiftUI)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("WIKI LOG")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(1.5)
            Spacer()
            Button {
                state.reload(vaultRoot: vaultRoot)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Reload log.md")

            Button {
                openLog()
            } label: {
                Image(systemName: "doc.text")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Open log.md in the editor")

            Button {
                state.hide()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close log")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(colorScheme == .dark ? Theme.separatorOpacityDark : Theme.separatorOpacity))
            .frame(height: 1)
            .padding(.horizontal, 12)
    }

    private var pendingBadge: some View {
        let count = controller.pendingOperation?.changes.count ?? 0
        let label = controller.pendingOperationLabel
        return Button {
            controller.presentPending()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(.tint)
                    .frame(width: 6, height: 6)
                Text("\(label) ready · \(count) change\(count == 1 ? "" : "s")")
                    .font(.callout)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open the \(label) diff sheet")
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let error = state.lastError {
            VStack(alignment: .leading, spacing: 6) {
                Label("Couldn't read log.md", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        } else if state.entries.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No operations logged yet.")
                    .font(.headline)
                Text("Accepted Capture / Chat / Review operations will appear here in reverse chronological order.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(state.entries) { entry in
                        WikiLogRow(entry: entry, openPath: openPath)
                        Divider().padding(.vertical, 2)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }
}

// MARK: - Row

private struct WikiLogRow: View {
    let entry: WikiLogEntry
    let openPath: (String) -> Void

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(Theme.Motion.smooth) { expanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: kindIcon)
                        .foregroundStyle(kindColor)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(expanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text(entry.timestamp)
                            Text("·")
                            Text(entry.kind)
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                if !entry.rationale.isEmpty {
                    Text(entry.rationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 22)
                        .padding(.top, 4)
                        .textSelection(.enabled)
                }
                if !entry.changes.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(entry.changes.enumerated()), id: \.offset) { _, change in
                            Button {
                                openPath(change.path)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(change.verb)
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(verbColor(change.verb))
                                        .frame(width: 46, alignment: .leading)
                                    Text(change.path)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 22)
                    .padding(.top, 6)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var kindIcon: String {
        switch entry.kind.lowercased() {
        case "capture", "ingest": return "tray.and.arrow.down"
        case "chat", "query": return "bubble.left"
        case "review", "lint": return "checkmark.shield"
        case "integrate": return "link"
        default: return "square.and.pencil"
        }
    }

    private var kindColor: Color {
        switch entry.kind.lowercased() {
        case "capture", "ingest": return .blue
        case "chat", "query": return .purple
        case "review", "lint": return .orange
        case "integrate": return .teal
        default: return .secondary
        }
    }

    private func verbColor(_ verb: String) -> Color {
        switch verb {
        case "create": return .green
        case "modify": return .blue
        case "delete": return .red
        default: return .secondary
        }
    }
}
