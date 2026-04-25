import SwiftUI
import AppKit
import ClearlyCore

/// Root view for the native macOS shell — two-column `NavigationSplitView`:
/// sidebar holds the folder-and-file outline, detail holds the editor +
/// preview + toolbar. Clicking a file in the sidebar opens it in the
/// detail; clicking a folder just expands/collapses it.
struct MacRootView: View {
    @Bindable var workspace: WorkspaceManager
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedFileURL: URL? = nil
    @State private var positionSyncID: String = UUID().uuidString
    @State private var showFormatPopover = false
    @State private var lastSidebarClickModifiers: NSEvent.ModifierFlags = []
    @State private var lastSidebarClickTime: Date? = nil
    @StateObject private var findState = FindState()
    @StateObject private var outlineState = OutlineState()
    @StateObject private var backlinksState = BacklinksState()
    @StateObject private var jumpToLineState = JumpToLineState()
    @State private var wikiController = WikiOperationController()
    @State private var wikiChat = WikiChatState()
    @State private var wikiLog = WikiLogState()
    @State private var wikiCapture = WikiCaptureState()

    var body: some View {
        if workspace.isFirstRun && workspace.locations.isEmpty && workspace.activeDocumentID == nil {
            WelcomeView(workspace: workspace)
        } else {
            splitView
        }
    }

    @ViewBuilder
    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MacFolderSidebar(
                workspace: workspace,
                selectedFileURL: $selectedFileURL
            )
            .background(SidebarClickModifierWatcher { mods, time in
                lastSidebarClickModifiers = mods
                lastSidebarClickTime = time
            })
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            VStack(spacing: 0) {
                MacTabBar(workspace: workspace)
                MacDetailColumn(
                    workspace: workspace,
                    findState: findState,
                    outlineState: outlineState,
                    backlinksState: backlinksState,
                    jumpToLineState: jumpToLineState,
                    wikiController: wikiController,
                    wikiChat: wikiChat,
                    wikiLog: wikiLog,
                    wikiCapture: wikiCapture,
                    positionSyncID: $positionSyncID,
                    showFormatPopover: $showFormatPopover
                )
            }
            .toolbar {
                MacDetailToolbar(
                    workspace: workspace,
                    findState: findState,
                    outlineState: outlineState,
                    backlinksState: backlinksState,
                    showFormatPopover: $showFormatPopover
                )
            }
        }
        .navigationTitle(windowTitle)
        .navigationDocument(workspace.currentFileURL ?? URL(fileURLWithPath: "/"))
        .onChange(of: selectedFileURL) { _, newURL in
            guard let url = newURL else { return }
            guard workspace.currentFileURL != url else { return }
            let isCmdClick: Bool = {
                guard let t = lastSidebarClickTime, Date().timeIntervalSince(t) < 0.25 else { return false }
                return lastSidebarClickModifiers.contains(.command)
            }()
            lastSidebarClickModifiers = []
            lastSidebarClickTime = nil
            if isCmdClick {
                workspace.openFileInNewTab(at: url)
            } else {
                workspace.openFile(at: url)
            }
        }
        .onChange(of: workspace.currentFileURL) { _, newURL in
            if selectedFileURL != newURL {
                selectedFileURL = newURL
            }
        }
    }

    private var windowTitle: String {
        guard let docID = workspace.activeDocumentID,
              let doc = workspace.openDocuments.first(where: { $0.id == docID }) else {
            return "Clearly"
        }
        return workspace.isDirty ? "\u{2022} \(doc.displayName)" : doc.displayName
    }
}
