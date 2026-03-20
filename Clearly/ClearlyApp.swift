import SwiftUI
import Sparkle

@main
struct ClearlyApp: App {
    @AppStorage("themePreference") private var themePreference = "system"
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 720, height: 900)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(after: .textEditing) {
                ViewModeCommands()
            }
            CommandGroup(after: .textFormatting) {
                FontSizeCommands()
            }
            CommandMenu("Format") {
                Button("Bold") {
                    NSApp.sendAction(#selector(ClearlyTextView.toggleBold(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("b", modifiers: .command)

                Button("Italic") {
                    NSApp.sendAction(#selector(ClearlyTextView.toggleItalic(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("Heading") {
                    NSApp.sendAction(#selector(ClearlyTextView.insertHeading(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Divider()

                Button("Link...") {
                    NSApp.sendAction(#selector(ClearlyTextView.insertLink(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }

        Settings {
            SettingsView(updater: updaterController.updater)
        }
    }
}

struct ViewModeCommands: View {
    @FocusedValue(\.viewMode) var mode

    var body: some View {
        Button("Editor") {
            mode?.wrappedValue = .edit
        }
        .keyboardShortcut("1", modifiers: .command)

        Button("Side by Side") {
            mode?.wrappedValue = .sideBySide
        }
        .keyboardShortcut("2", modifiers: .command)

        Button("Preview") {
            mode?.wrappedValue = .preview
        }
        .keyboardShortcut("3", modifiers: .command)
    }
}

// MARK: - Font Size Commands

struct FontSizeCommands: View {
    @AppStorage("editorFontSize") private var fontSize: Double = 16

    var body: some View {
        Button("Increase Font Size") {
            fontSize = min(fontSize + 1, 24)
        }
        .keyboardShortcut("+", modifiers: .command)

        Button("Decrease Font Size") {
            fontSize = max(fontSize - 1, 12)
        }
        .keyboardShortcut("-", modifiers: .command)
    }
}

// MARK: - Sparkle Check for Updates menu item

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private var observation: Any?

    init(updater: SPUUpdater) {
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, change in
            DispatchQueue.main.async {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }
}
