import SwiftUI
import KeyboardShortcuts

struct ScratchpadMenuBar: View {
    var manager: ScratchpadManager
    @Environment(\.openSettings) private var openSettings

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
                NSDocumentController.shared.newDocument(nil)
            }
        }
        .keyboardShortcut("n", modifiers: [.command])

        Button("Open Document") {
            performMenuBarAction {
                NSDocumentController.shared.openDocument(nil)
            }
        }
        .keyboardShortcut("o", modifiers: [.command])

        Divider()

        Button("Settings…") {
            performSettingsMenuBarAction()
        }
        .keyboardShortcut(",", modifiers: [.command])

        Button("Quit Clearly") {
            NSApp.terminate(nil)
        }
    }

    private func performMenuBarAction(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                action()
            }
        }
    }

    private func performSettingsMenuBarAction() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ClearlyAppDelegate.shared?.prepareForMenuBarSettingsActivation()
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                openSettings()
            }
        }
    }
}
