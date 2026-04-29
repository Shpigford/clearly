#if os(iOS)
import SwiftUI
import ClearlyCore

/// Vault-only folder tree picker presented as a sheet for the "Move…" action
/// in the file context menu. Mirrors the main sidebar's `OutlineGroup` pattern
/// with a folder-only filter, plus the vault root as a top-level destination.
struct FolderPickerSheet_iOS: View {
    let movingFile: VaultFile
    let onSelect: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(VaultSession.self) private var session
    @State private var folderTree: [FileNode] = []
    @State private var selection: URL?

    var body: some View {
        NavigationStack {
            List {
                if let rootURL = session.currentVault?.url {
                    rootRow(url: rootURL)
                }
                OutlineGroup(folderTree, children: \.displayChildren) { node in
                    folderRow(node)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Move \u{201C}\(displayTitle)\u{201D}")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        if let dest = selection {
                            onSelect(dest)
                            dismiss()
                        }
                    }
                    .disabled(!isMoveEnabled)
                }
            }
            .onAppear { rebuild() }
            .onChange(of: session.files) { _, _ in rebuild() }
        }
    }

    private var displayTitle: String {
        (movingFile.name as NSString).deletingPathExtension
    }

    private var currentParent: URL? {
        movingFile.url.deletingLastPathComponent().standardizedFileURL
    }

    private var isMoveEnabled: Bool {
        guard let dest = selection?.standardizedFileURL else { return false }
        return dest != currentParent
    }

    private func rootRow(url: URL) -> some View {
        let label = session.currentVault?.displayName ?? "Vault"
        return pickerRow(
            url: url,
            label: Label(label, systemImage: "tray.full")
        )
    }

    private func folderRow(_ node: FileNode) -> some View {
        pickerRow(
            url: node.url,
            label: Label(node.name, systemImage: "folder")
        )
    }

    private func pickerRow<L: View>(url: URL, label: L) -> some View {
        let standardized = url.standardizedFileURL
        let isSelected = selection?.standardizedFileURL == standardized
        let isCurrentParent = currentParent == standardized
        return HStack {
            label
                .foregroundStyle(isCurrentParent ? .secondary : .primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // Tapping the file's current folder is a no-op — picking it would
            // leave the Move button disabled and dangle a checkmark next to a
            // dead button.
            guard !isCurrentParent else { return }
            selection = url
        }
    }

    private func rebuild() {
        guard let rootURL = session.currentVault?.url else {
            folderTree = []
            return
        }
        let files = session.files
        Task.detached(priority: .userInitiated) {
            let raw = FileNode.buildTree(at: rootURL, including: files)
            let folders = raw.compactMap { Self.keepFolders($0) }
            await MainActor.run { folderTree = folders }
        }
    }

    private static func keepFolders(_ node: FileNode) -> FileNode? {
        guard node.isDirectory else { return nil }
        let filteredChildren = (node.children ?? []).compactMap { keepFolders($0) }
        return FileNode(
            name: node.name,
            url: node.url,
            isHidden: node.isHidden,
            children: filteredChildren
        )
    }
}
#endif
