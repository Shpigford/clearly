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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                activateDocumentApp()
                NSDocumentController.shared.newDocument(nil)
            }
        }
        .keyboardShortcut("n", modifiers: [.command])

        Button("Open Document") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                activateDocumentApp()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSDocumentController.shared.openDocument(nil)
                    // Ensure the open panel is frontmost
                    DispatchQueue.main.async {
                        for window in NSApp.windows where window is NSOpenPanel {
                            window.orderFrontRegardless()
                        }
                    }
                }
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
}
