import SwiftUI
import ClearlyCore

@main
struct ClearlyApp_iOS: App {
    @State private var vaultSession = VaultSession()
    @State private var tabController = IPadTabController()
    @State private var expansionState = IOSExpansionState()

    var body: some Scene {
        WindowGroup {
            ContentRoot_iOS(tabController: tabController)
                .environment(vaultSession)
                .environment(expansionState)
                .task {
                    await vaultSession.restoreFromPersistence()
                }
                .onChange(of: vaultSession.currentVault?.url) { _, newURL in
                    expansionState.bind(to: newURL)
                }
        }
    }
}

/// Top-level view that picks between the iPhone `NavigationStack` path and
/// the iPad 3-column `NavigationSplitView` path based on horizontal size
/// class. Both the `VaultSession` (via environment) and the
/// `IPadTabController` (via `@State` on the app scene) live outside this
/// view so flipping between the two layouts doesn't lose user state.
struct ContentRoot_iOS: View {
    @Environment(\.horizontalSizeClass) private var hSizeClass

    let tabController: IPadTabController

    var body: some View {
        Group {
            if hSizeClass == .regular {
                IPadRootView(controller: tabController)
            } else {
                FolderListView_iOS()
            }
        }
    }
}
