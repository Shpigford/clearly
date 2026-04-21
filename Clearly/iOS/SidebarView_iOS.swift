import SwiftUI
import ClearlyCore

struct SidebarView_iOS: View {
    @Environment(VaultSession.self) private var session
    @State private var showWelcome: Bool = false
    @State private var showTags: Bool = false

    @State private var renameTarget: VaultFile?
    @State private var renameDraft: String = ""
    @State private var renameError: String?

    @State private var deleteTarget: VaultFile?
    @State private var operationError: String?

    var body: some View {
        @Bindable var session = session
        NavigationStack(path: $session.navigationPath) {
            VStack(spacing: 0) {
                if let progress = session.indexProgress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(height: 2)
                        .tint(.accentColor)
                }
                Group {
                    if session.currentVault == nil {
                        placeholder
                    } else if session.files.isEmpty && session.isLoading {
                        ProgressView("Loading…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if session.files.isEmpty {
                        emptyVault
                    } else {
                        fileList
                    }
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        session.isShowingQuickSwitcher = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Search notes")
                    .disabled(session.currentVault == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showTags = true
                    } label: {
                        Image(systemName: "tag")
                    }
                    .accessibilityLabel("Browse tags")
                    .disabled(session.currentVault == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showWelcome = true
                    } label: {
                        Image(systemName: "folder")
                    }
                    .accessibilityLabel("Change vault")
                }
            }
            .refreshable {
                session.refresh()
            }
            .background {
                QuickSwitcherShortcuts()
            }
        }
        .fullScreenCover(isPresented: shouldShowWelcomeBinding) {
            WelcomeView_iOS()
                .interactiveDismissDisabled(session.currentVault == nil)
                .onChange(of: session.currentVault?.id) { _, _ in
                    if session.currentVault != nil {
                        showWelcome = false
                    }
                }
        }
        .sheet(isPresented: $session.isShowingQuickSwitcher) {
            QuickSwitcherSheet_iOS()
                .environment(session)
        }
        .sheet(isPresented: $showTags) {
            TagsSheet_iOS()
                .environment(session)
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

    private var shouldShowWelcomeBinding: Binding<Bool> {
        Binding(
            get: { session.currentVault == nil || showWelcome },
            set: { newValue in
                if !newValue { showWelcome = false }
            }
        )
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

    private var navTitle: String {
        session.currentVault?.displayName ?? "Clearly"
    }

    private var placeholder: some View {
        Color.clear
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
            NavigationLink(value: file) {
                HStack(spacing: 10) {
                    Image(systemName: file.isPlaceholder ? "icloud.and.arrow.down" : "doc.text")
                        .foregroundStyle(file.isPlaceholder ? .secondary : .primary)
                        .frame(width: 22)
                    Text(file.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
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
        .navigationDestination(for: VaultFile.self) { file in
            RawTextDetailView_iOS(file: file)
        }
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
            } catch {
                operationError = error.localizedDescription
            }
        }
    }
}
