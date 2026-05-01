import SwiftUI
import AppKit
import ClearlyCore

/// Root view for the native macOS shell. By default a two-column
/// `NavigationSplitView`: sidebar holds the folder-and-file outline, detail
/// holds the editor + preview + toolbar. Clicking a file in the sidebar
/// opens it in the detail; clicking a folder just expands/collapses it.
///
/// When `@AppStorage("layoutMode")` is set to `.threePane`, a Notes-style
/// middle column (`MacNoteListView`) appears between sidebar and editor,
/// listing notes inside the currently-selected folder.
struct MacRootView: View {
    @Bindable var workspace: WorkspaceManager
    @AppStorage(LayoutMode.storageKey) private var layoutMode: LayoutMode = .twoPane
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedFileURL: URL? = nil
    @State private var positionSyncID: String = UUID().uuidString
    @State private var showFormatPopover = false
    @State private var lastSidebarClickModifiers: NSEvent.ModifierFlags = []
    @State private var lastSidebarClickTime: Date? = nil
    @State private var lastClickSource: ClickSource = .none
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
        // Always a 3-column NavigationSplitView so SwiftUI keeps the same
        // structural identity across layout-mode flips. Switching the
        // overload (2-col ↔ 3-col) would tear down the detail subtree —
        // and with it the NSTextView, undo stack, and WKWebView — leaking
        // observers and script-message handlers on every flip.
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarColumn
        } content: {
            middleColumn
        } detail: {
            detailColumn
        }
        .navigationTitle(windowTitle)
        .navigationDocument(workspace.currentFileURL ?? URL(fileURLWithPath: "/"))
        .onChange(of: selectedFileURL) { _, newURL in
            guard let url = newURL else { return }
            // Sidebar clicks on a file should also move the active folder to
            // its parent, so the middle list scrolls to and highlights the
            // file. List clicks must NOT do this — opening a note from the
            // middle list keeps the user's current scope intact.
            // `vaultIndexAndRelativePath` rejects anything outside a
            // registered vault, so pinned/recents across vaults are safe.
            let cameFromSidebar: Bool = {
                guard lastClickSource == .sidebar,
                      let t = lastSidebarClickTime,
                      Date().timeIntervalSince(t) < 0.25 else { return false }
                return true
            }()
            if cameFromSidebar {
                let parent = url.deletingLastPathComponent()
                if workspace.selectedFolderURL?.standardizedFileURL != parent.standardizedFileURL,
                   workspace.vaultIndexAndRelativePath(for: parent) != nil {
                    workspace.setSelectedFolder(parent)
                }
            }

            guard workspace.currentFileURL != url else { return }
            let isCmdClick: Bool = {
                guard let t = lastSidebarClickTime, Date().timeIntervalSince(t) < 0.25 else { return false }
                return lastSidebarClickModifiers.contains(.command)
            }()
            lastSidebarClickModifiers = []
            lastSidebarClickTime = nil
            lastClickSource = .none
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

    /// Middle column. In 3-pane mode, hosts the Notes-style list. In
    /// 2-pane mode, collapses to a zero-width placeholder so the enclosing
    /// `NavigationSplitView` keeps its 3-column shape — flipping shape
    /// would destroy the detail subtree and rebuild the editor + WKWebView
    /// from scratch on every toggle.
    @ViewBuilder
    private var middleColumn: some View {
        if layoutMode == .threePane {
            MacNoteListView(
                workspace: workspace,
                selectedNoteURL: $selectedFileURL
            )
            // Same probe as the sidebar — lets the existing
            // `onChange(of: selectedFileURL)` handler route cmd-clicks to
            // `openFileInNewTab` when the user picks a row in the list.
            .background(SidebarClickModifierWatcher { mods, time in
                lastSidebarClickModifiers = mods
                lastSidebarClickTime = time
                lastClickSource = .list
            })
            .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
        } else {
            Color.clear
                .frame(width: 0)
                .navigationSplitViewColumnWidth(min: 0, ideal: 0, max: 0)
        }
    }

    @ViewBuilder
    private var sidebarColumn: some View {
        MacFolderSidebar(
            workspace: workspace,
            selectedFileURL: $selectedFileURL
        )
        .background(SidebarClickModifierWatcher { mods, time in
            lastSidebarClickModifiers = mods
            lastSidebarClickTime = time
            lastClickSource = .sidebar
        })
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
    }

    @ViewBuilder
    private var detailColumn: some View {
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
                wikiController: wikiController,
                showFormatPopover: $showFormatPopover
            )
        }
    }

    /// Where the most recent left-mouse-down was observed. Lets the
    /// `selectedFileURL` observer distinguish "sidebar click that should
    /// move the active folder" from "list click that must NOT move the
    /// active folder". Reset to `.none` after each consumed click.
    private enum ClickSource {
        case none, sidebar, list
    }

    private var windowTitle: String {
        guard let docID = workspace.activeDocumentID,
              let doc = workspace.openDocuments.first(where: { $0.id == docID }) else {
            return "Clearly"
        }
        return workspace.isDirty ? "\u{2022} \(doc.displayName)" : doc.displayName
    }
}
