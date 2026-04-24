import SwiftUI
import ClearlyCore

/// Trailing-edge panel that renders `log.md` as a scrubbable timeline of
/// accepted operations. Each entry is expandable to show the rationale and
/// the list of file changes that landed. Click a change row to open that
/// file in the editor.
struct WikiLogSidebar: View {
    @Bindable var state: WikiLogState
    let vaultRoot: URL?
    let openPath: (String) -> Void
    let openLog: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
        .background(Theme.backgroundColorSwiftUI)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
            Text("Log")
                .font(.headline)
            Spacer()
            Button {
                state.reload(vaultRoot: vaultRoot)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Reload log.md")

            Button {
                openLog()
            } label: {
                Image(systemName: "doc.text")
            }
            .buttonStyle(.plain)
            .help("Open log.md in the editor")

            Button {
                state.hide()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close log")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
                Text("Accepted Ingest / Query / Lint operations will appear here in reverse chronological order.")
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
        case "ingest": return "tray.and.arrow.down"
        case "query": return "bubble.left"
        case "lint": return "checkmark.shield"
        default: return "square.and.pencil"
        }
    }

    private var kindColor: Color {
        switch entry.kind.lowercased() {
        case "ingest": return .blue
        case "query": return .purple
        case "lint": return .orange
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
