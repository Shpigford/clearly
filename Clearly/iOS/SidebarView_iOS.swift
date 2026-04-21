import SwiftUI
import ClearlyCore

struct SidebarView_iOS: View {
    @Environment(VaultSession.self) private var session
    @State private var showWelcome: Bool = false

    var body: some View {
        NavigationStack {
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
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
    }

    private var shouldShowWelcomeBinding: Binding<Bool> {
        Binding(
            get: { session.currentVault == nil || showWelcome },
            set: { newValue in
                if !newValue { showWelcome = false }
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
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: VaultFile.self) { file in
            RawTextDetailView_iOS(file: file)
        }
    }
}
