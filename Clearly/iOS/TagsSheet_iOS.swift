import SwiftUI
import ClearlyCore

/// Two-step tag browser. Root view lists every tag with its file count; tapping
/// a tag pushes a filtered file list onto the sheet's internal NavigationStack.
/// Tapping a file dismisses the sheet and appends the file to
/// `vault.navigationPath` (the app-level sidebar stack).
struct TagsSheet_iOS: View {
    @Environment(VaultSession.self) private var vault
    @Environment(\.dismiss) private var dismiss

    @State private var tags: [(tag: String, count: Int)] = []

    var body: some View {
        NavigationStack {
            Group {
                if tags.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tag")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("No tags")
                            .font(.headline)
                        Text("Add `#tag` anywhere in a note to see it here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(tags, id: \.tag) { entry in
                        NavigationLink(value: entry.tag) {
                            HStack {
                                Text("#\(entry.tag)")
                                    .font(.system(size: 15, weight: .medium))
                                Spacer()
                                Text("\(entry.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: String.self) { tag in
                TaggedFilesView(tag: tag) { file in
                    dismiss()
                    vault.navigationPath.append(file)
                }
            }
        }
        .onAppear { refresh() }
        .onChange(of: vault.indexProgress) { _, newValue in
            if newValue == nil { refresh() }
        }
    }

    private func refresh() {
        tags = vault.currentIndex?.allTags() ?? []
    }
}

private struct TaggedFilesView: View {
    @Environment(VaultSession.self) private var vault
    let tag: String
    let onSelect: (VaultFile) -> Void

    private var files: [VaultFile] { vault.filesForTag(tag) }

    var body: some View {
        Group {
            if files.isEmpty {
                Text("No files tagged `#\(tag)`")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(files) { file in
                    Button { onSelect(file) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            Text(file.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("#\(tag)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
