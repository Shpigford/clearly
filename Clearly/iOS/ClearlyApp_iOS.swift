import SwiftUI
import ClearlyCore

@main
struct ClearlyApp_iOS: App {
    @State private var vaultSession = VaultSession()

    var body: some Scene {
        WindowGroup {
            SidebarView_iOS()
                .environment(vaultSession)
                .task {
                    await vaultSession.restoreFromPersistence()
                }
        }
    }
}
