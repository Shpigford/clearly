import SwiftUI
import ClearlyCore

@main
struct ClearlyApp_iOS: App {
    @State private var vaultSession = VaultSession()
    @State private var tabController = IPadTabController()

    var body: some Scene {
        WindowGroup {
            ContentRoot_iOS(tabController: tabController)
                .environment(vaultSession)
                .task {
                    await vaultSession.restoreFromPersistence()
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
