import SwiftUI
import KeyboardShortcuts

struct ScratchpadMenuBar: View {
    var manager: ScratchpadManager

    var body: some View {
        Button("New Scratchpad") {
            manager.createScratchpad()
        }
        .keyboardShortcut(for: .newScratchpad)

        Divider()

        if !manager.scratchpads.isEmpty {
            ForEach(manager.scratchpads) { pad in
                Button(pad.displayTitle) {
                    manager.focusScratchpad(id: pad.id)
                }
            }

            Button("Close All Scratchpads") {
                manager.closeAll()
            }

            Divider()
        }

        Button("New Document") {
            performMenuBarAction {
                WorkspaceManager.shared.createUntitledDocument()
            }
        }
        .keyboardShortcut("n", modifiers: [.command])

        Button("Show Workspace") {
            performMenuBarAction {
                WindowRouter.shared.showMainWindow()
            }
        }

        Button("Open Document") {
            performMenuBarAction {
                WorkspaceManager.shared.showOpenPanel()
            }
        }
        .keyboardShortcut("o", modifiers: [.command])

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: [.command])

        Button("Quit Clearly") {
            NSApp.terminate(nil)
        }
    }

    private func performMenuBarAction(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            activateDocumentApp()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                WindowRouter.shared.showMainWindow()
                action()
            }
        }
    }
}
