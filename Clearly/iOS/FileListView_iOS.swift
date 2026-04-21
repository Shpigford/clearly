import SwiftUI
import ClearlyCore

/// Flat file list used by both the iPhone `SidebarView_iOS` (wrapped in the
/// sidebar's NavigationStack) and the iPad `IPadRootView`'s content column.
/// The caller provides an `onOpen(_:)` closure — iPhone appends to
/// `VaultSession.navigationPath`; iPad routes through `IPadTabController`.
struct FileListView_iOS: View {
    @Environment(VaultSession.self) private var session

    /// Invoked when a row is tapped. iPhone pushes to its nav stack; iPad
    /// activates/opens a tab.
    let onOpen: (VaultFile) -> Void
    let onDelete: (VaultFile) -> Void

    @State private var renameTarget: VaultFile?
    @State private var renameDraft: String = ""
    @State private var renameError: String?

    @State private var deleteTarget: VaultFile?
    @State private var operationError: String?

    var body: some View {
        Group {
            if session.currentVault == nil {
                Color.clear
            } else if session.files.isEmpty && session.isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if session.files.isEmpty {
                emptyVault
            } else {
                fileList
            }
        }
        .alert("Rename note", isPresented: renameAlertBinding) {
            TextField("Name", text: $renameDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") { commitRename() }
        } message: {
            if let err = renameError {
                Text(err)
            } else {
                Text("Enter a new name (extension preserved).")
            }
        }
        .confirmationDialog(
            deleteTarget.map { "Delete \u{201C}\($0.name)\u{201D}?" } ?? "",
            isPresented: deleteConfirmBinding,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("This can't be undone from within Clearly.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { operationError = nil }
        } message: {
            Text(operationError ?? "")
        }
    }

    private var emptyVault: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
            Text("No notes yet")
                .font(.headline)
            Text("Drop a `.md` file into this folder via Files to get started.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fileList: some View {
        List(session.files) { file in
            Button {
                onOpen(file)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: file.isPlaceholder ? "icloud.and.arrow.down" : "doc.text")
                        .foregroundStyle(file.isPlaceholder ? .secondary : .primary)
                        .frame(width: 22)
                    Text(file.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    beginRename(file)
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    deleteTarget = file
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { newValue in
                if !newValue {
                    renameTarget = nil
                    renameError = nil
                }
            }
        )
    }

    private var deleteConfirmBinding: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { newValue in
                if !newValue { deleteTarget = nil }
            }
        )
    }

    private func beginRename(_ file: VaultFile) {
        renameTarget = file
        renameError = nil
        renameDraft = (file.name as NSString).deletingPathExtension
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        let draft = renameDraft
        renameTarget = nil
        Task {
            do {
                try await session.renameFile(target, to: draft)
            } catch VaultSessionError.readFailed(let msg) {
                operationError = msg
            } catch {
                operationError = error.localizedDescription
            }
        }
    }

    private func commitDelete() {
        guard let target = deleteTarget else { return }
        deleteTarget = nil
        Task {
            do {
                try await session.deleteFile(target)
                await MainActor.run { onDelete(target) }
            } catch {
                operationError = error.localizedDescription
            }
        }
    }
}
