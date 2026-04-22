import SwiftUI
import ClearlyCore

/// iPhone (and iPad compact) detail view. Owns its own `IOSDocumentSession`
/// tied to the view's lifetime — pushed on navigation in, closed on pop.
/// The iPad regular-width path uses `IPadDetailView_iOS` instead, where a
/// tab controller owns the session across tab switches.
struct RawTextDetailView_iOS: View {
    @Environment(VaultSession.self) private var vault
    @Environment(\.scenePhase) private var scenePhase

    let file: VaultFile

    @State private var document = IOSDocumentSession()
    @State private var viewMode: ViewMode = .edit
    @StateObject private var backlinksState = BacklinksState()
    @StateObject private var outlineState = OutlineState()

    var body: some View {
        DocumentDetailBody(
            session: document,
            file: file,
            viewMode: $viewMode,
            outlineState: outlineState,
            backlinksState: backlinksState,
            onOpenFile: { vault.navigationPath.append($0) }
        )
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .background {
            QuickSwitcherShortcuts()
        }
        .task(id: file.id) {
            await document.open(file, via: vault)
            if document.errorMessage == nil {
                vault.markRecent(file)
                outlineState.parseHeadings(from: document.text)
                refreshBacklinks()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                Task { await document.flush() }
            }
        }
        .onDisappear {
            Task { await document.close() }
        }
    }

    /// Pulls the file name from the live document session first so the title
    /// tracks auto-rename (Notes-style `untitled.md` → derived-from-content).
    /// Falls back to the captured `file.name` while the session is loading.
    private var titleText: String {
        let name = document.file?.name ?? file.name
        return document.isDirty ? "• \(name)" : name
    }

    private func refreshBacklinks() {
        let indexes = [vault.currentIndex].compactMap { $0 }
        backlinksState.update(for: file.url, using: indexes)
    }
}
