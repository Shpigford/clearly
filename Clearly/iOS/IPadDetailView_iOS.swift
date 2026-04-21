#if os(iOS)
import SwiftUI
import ClearlyCore

/// Detail column for the iPad regular-width layout. Top: tab bar. Below:
/// active tab's `DocumentDetailBody`. Shows an empty state when no tabs
/// are open. Scene-phase flush is handled at the root; this view is
/// layout-only.
struct IPadDetailView_iOS: View {
    @Environment(VaultSession.self) private var vault
    let controller: IPadTabController

    var body: some View {
        Group {
            if controller.tabs.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    IPadTabBar(controller: controller)
                    if let tab = controller.activeTab {
                        activeBody(for: tab)
                            .id(tab.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func activeBody(for tab: IPadTab) -> some View {
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
                controller.openOrActivate(file)
            }
        )
        .environment(vault)
        .navigationTitle(titleFor(tab))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func titleFor(_ tab: IPadTab) -> String {
        let name = tab.session.file?.name ?? tab.file.name
        return tab.session.isDirty ? "• \(name)" : name
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No Note Open")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Pick a note from the list, or press ⌘K to search.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
