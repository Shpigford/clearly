import SwiftUI
import ClearlyCore

/// Root view for the native macOS shell. Three-column `NavigationSplitView`:
/// folder sidebar, notes list, detail column with editor + preview, toolbar,
/// and inspector panels. Mirrors `IPadRootView.swift` structurally while
/// diverging where macOS conventions call for it (unified toolbar, ShareLink,
/// native `.inspector()`).
struct MacRootView: View {
    @Bindable var workspace: WorkspaceManager
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var sidebarSelection: SidebarSelection? = nil
    @State private var selectedFileURL: URL? = nil
    @State private var searchQuery: String = ""

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MacFolderSidebar(
                workspace: workspace,
                selection: $sidebarSelection
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } content: {
            MacNotesListColumn(
                workspace: workspace,
                selection: sidebarSelection,
                selectedFileURL: $selectedFileURL,
                searchQuery: $searchQuery
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 400)
        } detail: {
            VStack(spacing: 0) {
                MacTabBar(workspace: workspace)
                MacDetailColumn(workspace: workspace)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $searchQuery, placement: .toolbar, prompt: "Search")
        .onAppear {
            defaultSelectionIfNeeded()
        }
        .onChange(of: workspace.locations.map(\.id)) { _, _ in
            defaultSelectionIfNeeded()
        }
        .onChange(of: selectedFileURL) { _, newURL in
            guard let url = newURL else { return }
            if workspace.currentFileURL != url {
                workspace.openFile(at: url)
            }
        }
        .onChange(of: workspace.currentFileURL) { _, newURL in
            if selectedFileURL != newURL {
                selectedFileURL = newURL
            }
        }
    }

    private func defaultSelectionIfNeeded() {
        if sidebarSelection == nil, let first = workspace.locations.first {
            sidebarSelection = .allNotes(locationID: first.id)
        }
    }
}
