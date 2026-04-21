import SwiftUI
import ClearlyCore

/// Compact-width (iPhone, iPad split-screen narrow) root. Sidebar + file list
/// live in a single `NavigationStack` push/pop flow; detail view opens
/// full-screen on tap. For the regular-width iPad path see `IPadRootView`.
struct SidebarView_iOS: View {
    @Environment(VaultSession.self) private var session
    @State private var showWelcome: Bool = false
    @State private var showTags: Bool = false

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
                FileListView_iOS(onOpen: { file in
                    session.navigationPath.append(file)
                }, onDelete: { _ in
                })
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
            .navigationDestination(for: VaultFile.self) { file in
                RawTextDetailView_iOS(file: file)
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
            QuickSwitcherSheet_iOS(onOpenFile: { file in
                if session.navigationPath != [file] {
                    session.navigationPath = [file]
                }
                session.markRecent(file)
            })
            .environment(session)
        }
        .sheet(isPresented: $showTags) {
            TagsSheet_iOS(onOpenFile: { file in
                session.navigationPath.append(file)
            })
                .environment(session)
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
}
