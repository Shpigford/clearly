import SwiftUI
import ClearlyCore

/// Presents the linked + unlinked mentions for the currently-open note. Reuses
/// the shared `BacklinksState` from `ClearlyCore`. The "Link" action on Mac's
/// BacklinksView is intentionally dropped in Phase 10 — in-file wiki-link
/// insertion requires coordinated text rewriting on a potentially-closed file.
struct BacklinksSheet_iOS: View {
    @Environment(VaultSession.self) private var vault
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var backlinksState: BacklinksState

    private var totalCount: Int {
        backlinksState.backlinks.count + backlinksState.unlinkedMentions.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if totalCount == 0 {
                    VStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No backlinks")
                            .font(.headline)
                        Text("No other notes link to this file.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if !backlinksState.backlinks.isEmpty {
                            Section("Linked") {
                                ForEach(backlinksState.backlinks) { backlink in
                                    row(for: backlink)
                                }
                            }
                        }
                        if !backlinksState.unlinkedMentions.isEmpty {
                            Section("Unlinked") {
                                ForEach(backlinksState.unlinkedMentions) { backlink in
                                    row(for: backlink)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Backlinks\(totalCount > 0 ? " (\(totalCount))" : "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(for backlink: Backlink) -> some View {
        Button {
            open(backlink)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(backlink.sourceFilename)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !backlink.contextLine.isEmpty {
                    Text(backlink.contextLine)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func open(_ backlink: Backlink) {
        let url = backlink.vaultRootURL.appendingPathComponent(backlink.sourcePath)
        let match = vault.files.first {
            $0.url.standardizedFileURL == url.standardizedFileURL
        } ?? VaultFile(
            url: url,
            name: url.lastPathComponent,
            modified: nil,
            isPlaceholder: false
        )
        dismiss()
        vault.navigationPath.append(match)
    }
}
