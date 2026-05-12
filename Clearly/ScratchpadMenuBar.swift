import SwiftUI
import KeyboardShortcuts

struct ScratchpadMenuBar: View {
    var manager: ScratchpadManager
    var store: ScratchpadStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Open Scratchpad") {
            performMenuBarAction {
                manager.showOrFocus()
            }
        }
        .keyboardShortcut(for: .newScratchpad)

        Button("New Scratchpad") {
            performMenuBarAction {
                manager.createAndShowNew()
            }
        }

        if !store.notes.isEmpty {
            Divider()

            Menu("Recent Scratchpads") {
                ForEach(store.notes.prefix(8)) { note in
                    Button(note.title.isEmpty ? ScratchpadNote.titlePlaceholder : note.title) {
                        performMenuBarAction {
                            manager.select(note: note)
                            manager.showOrFocus()
                        }
                    }
                }
            }
        }

        Divider()

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
            ClearlyAppDelegate.shared?.requestFullQuitFromMenuBar()
        }
    }

    private func performMenuBarAction(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ClearlyAppDelegate.shared?.ensureRegularAndActivate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                action()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }

    private func performSettingsMenuBarAction() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ClearlyAppDelegate.shared?.prepareForMenuBarSettingsActivation()
            ClearlyAppDelegate.shared?.ensureRegularAndActivate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                openSettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }
}
