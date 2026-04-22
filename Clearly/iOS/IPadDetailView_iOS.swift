#if os(iOS)
import SwiftUI
import ClearlyCore

/// Detail column for the iPad regular-width layout. Renders the active
/// document's `DocumentDetailBody`, or a `ContentUnavailableView` empty
/// state when no document is open. Single-document focus — the
/// sorted-by-recency file list in the sidebar serves as the implicit
/// "tab bar"; tapping a row replaces what's in this pane.
struct IPadDetailView_iOS: View {
    @Environment(VaultSession.self) private var vault
    let controller: IPadTabController

    var body: some View {
        if let tab = controller.activeTab {
            DocumentDetailBody(
                session: tab.session,
                file: tab.file,
                viewMode: Binding(
                    get: { tab.viewMode },
                    set: { tab.viewMode = $0 }
                ),
                outlineState: tab.outlineState,
                backlinksState: tab.backlinksState,
                onOpenFile: { file in
                    controller.openExclusive(file)
                }
            )
            .id(tab.id)
            .environment(vault)
            .navigationTitle(titleFor(tab))
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView(
                "No Note Open",
                systemImage: "doc.text",
                description: Text("Tap a note in the list, or press ⌘N to start a new one.")
            )
        }
    }

    private func titleFor(_ tab: IPadTab) -> String {
        let name = tab.session.file?.name ?? tab.file.name
        return tab.session.isDirty ? "• \(name)" : name
    }
}
#endif
