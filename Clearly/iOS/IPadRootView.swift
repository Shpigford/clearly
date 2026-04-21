#if os(iOS)
import SwiftUI
import ClearlyCore

/// Regular-width (iPad) root. 3-column `NavigationSplitView` (sidebar |
/// file list | detail with tab bar). iOS 17 auto-collapses to a 2-column
/// presentation on smaller iPads / portrait orientation.
///
/// The compact-width path (iPhone, iPad split-screen narrow) uses
/// `SidebarView_iOS`. Root selection happens in `ContentRoot_iOS`.
struct IPadRootView: View {
    @Environment(VaultSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    let controller: IPadTabController

    @State private var showWelcome: Bool = false
    @State private var showTags: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var session = session
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } content: {
            contentColumn
        } detail: {
            NavigationStack {
                IPadDetailView_iOS(controller: controller)
            }
        }
        .navigationSplitViewStyle(.balanced)
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
                controller.openOrActivate(file)
            })
            .environment(session)
        }
        .sheet(isPresented: $showTags) {
            TagsSheet_iOS(onOpenFile: { file in
                controller.openOrActivate(file)
            })
                .environment(session)
        }
        .background {
            QuickSwitcherShortcuts()
            IPadKeyboardShortcuts(controller: controller)
        }
        .onChange(of: session.currentVault?.url) { _, _ in
            controller.bind(to: session)
        }
        .onChange(of: session.files) { _, _ in
            controller.restoreIfNeeded(vault: session)
            controller.reconcileTabURLs()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                flushAllTabs()
            }
        }
        .onAppear {
            controller.bind(to: session)
        }
    }

    // MARK: - Sidebar column

    private var sidebarColumn: some View {
        List {
            if session.currentVault != nil {
                Section {
                    Button {
                        session.isShowingQuickSwitcher = true
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    Button {
                        showTags = true
                    } label: {
                        Label("Tags", systemImage: "tag")
                    }
                }
                Section {
                    Button {
                        showWelcome = true
                    } label: {
                        Label("Change Vault", systemImage: "folder")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Content (file list) column

    private var contentColumn: some View {
        VStack(spacing: 0) {
            if let progress = session.indexProgress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(height: 2)
                    .tint(.accentColor)
            }
            FileListView_iOS(onOpen: { file in
                controller.openOrActivate(file)
            }, onDelete: { file in
                controller.closeTabs(matching: file)
            })
        }
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            session.refresh()
        }
    }

    // MARK: - Helpers

    private var navTitle: String {
        session.currentVault?.displayName ?? "Clearly"
    }

    private var shouldShowWelcomeBinding: Binding<Bool> {
        Binding(
            get: { session.currentVault == nil || showWelcome },
            set: { newValue in
                if !newValue { showWelcome = false }
            }
        )
    }

    private func flushAllTabs() {
        for tab in controller.tabs {
            Task { await tab.session.flush() }
        }
    }
}

/// Hidden-button hardware-keyboard shortcuts for the iPad tab bar. Mirrors
/// `QuickSwitcherShortcuts`'s pattern so the shortcuts stay registered
/// regardless of which column owns focus.
struct IPadKeyboardShortcuts: View {
    @Environment(VaultSession.self) private var session
    let controller: IPadTabController

    var body: some View {
        ZStack {
            Color.clear
            Button("New Tab") {
                session.isShowingQuickSwitcher = true
            }
            .keyboardShortcut("t", modifiers: .command)
            .hidden()

            Button("Close Tab") {
                controller.closeActiveTab()
            }
            .keyboardShortcut("w", modifiers: .command)
            .hidden()

            ForEach(1...9, id: \.self) { slot in
                Button("Jump to Tab \(slot)") {
                    controller.activate(at: slot - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(slot)")), modifiers: .command)
                .hidden()
            }
        }
        .accessibilityHidden(true)
        .disabled(session.currentVault == nil)
    }
}
#endif
