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
                    #if DEBUG
                    if attachDebugFixtureVaultIfAvailable() {
                        return
                    }
                    #endif
                    await vaultSession.restoreFromPersistence()
                }
                .onChange(of: vaultSession.currentVault?.url) { _, newURL in
                    expansionState.bind(to: newURL)
                }
        }
    }

    #if DEBUG
    @MainActor
    private func attachDebugFixtureVaultIfAvailable() -> Bool {
        guard let bundledFixture = Bundle.main.resourceURL?
            .appendingPathComponent("DebugFixtureVault", isDirectory: true),
            FileManager.default.fileExists(atPath: bundledFixture.path) else {
            return false
        }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: bundledFixture,
                includingPropertiesForKeys: nil
            )
            guard !contents.isEmpty else { return false }

            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let writableFixture = documents.appendingPathComponent("DebugFixtureVault", isDirectory: true)
            if FileManager.default.fileExists(atPath: writableFixture.path) {
                try FileManager.default.removeItem(at: writableFixture)
            }
            try FileManager.default.copyItem(at: bundledFixture, to: writableFixture)
            vaultSession.attach(VaultLocation(kind: .local, url: writableFixture))
            return true
        } catch {
            DiagnosticLog.log("iOS debug fixture vault failed: \(error.localizedDescription)")
            return false
        }
    }
    #endif
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
