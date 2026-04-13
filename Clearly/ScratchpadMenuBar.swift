import SwiftUI
import KeyboardShortcuts

struct ScratchpadMenuBar: View {
    var manager: ScratchpadManager

    var body: some View {
        Button(L10n.string("scratchpad.newScratchpad", defaultValue: "New Scratchpad")) {
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

            Button(L10n.string("scratchpad.closeAll", defaultValue: "Close All Scratchpads")) {
                manager.closeAll()
            }

            Divider()
        }

        Button(L10n.string("app.menu.newDocument", defaultValue: "New Document")) {
            performMenuBarAction {
                WorkspaceManager.shared.createUntitledDocument()
            }
        }
        .keyboardShortcut("n", modifiers: [.command])

        Button(L10n.string("scratchpad.showWorkspace", defaultValue: "Show Workspace")) {
            performMenuBarAction {
                WindowRouter.shared.showMainWindow()
            }
        }

        Button(L10n.string("scratchpad.openDocument", defaultValue: "Open Document")) {
            performMenuBarAction {
                WorkspaceManager.shared.showOpenPanel()
            }
        }
        .keyboardShortcut("o", modifiers: [.command])

        Divider()

        SettingsLink {
            Text(L10n.string("scratchpad.settings", defaultValue: "Settings…"))
        }
        .keyboardShortcut(",", modifiers: [.command])

        Button(L10n.string("scratchpad.quit", defaultValue: "Quit Clearly")) {
            NSApp.terminate(nil)
        }
    }

    private func performMenuBarAction(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            activateDocumentApp()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                action()
            }
        }
    }
}
