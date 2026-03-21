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
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 720, height: 900)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            CommandGroup(after: .importExport) {
                ExportPDFCommand()
            }
            CommandGroup(replacing: .printItem) {
                PrintCommand()
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

                Button("Strikethrough") {
                    NSApp.sendAction(#selector(ClearlyTextView.toggleStrikethrough(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])

                Button("Heading") {
                    NSApp.sendAction(#selector(ClearlyTextView.insertHeading(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Divider()

                Button("Link...") {
                    NSApp.sendAction(#selector(ClearlyTextView.insertLink(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Image...") {
                    NSApp.sendAction(#selector(ClearlyTextView.insertImage(_:)), to: nil, from: nil)
                }

                Divider()

                Button("Bullet List") {
                    NSApp.sendAction(#selector(ClearlyTextView.toggleBulletList(_:)), to: nil, from: nil)
                }

                Button("Numbered List") {
                    NSApp.sendAction(#selector(ClearlyTextView.toggleNumberedList(_:)), to: nil, from: nil)
                }

                Button("Todo") {
                    NSApp.sendAction(#selector(ClearlyTextView.toggleTodoList(_:)), to: nil, from: nil)
                }

                Divider()

                Button("Quote") {
                    NSApp.sendAction(#selector(ClearlyTextView.toggleBlockquote(_:)), to: nil, from: nil)
                }

                Button("Horizontal Rule") {
                    NSApp.sendAction(#selector(ClearlyTextView.insertHorizontalRule(_:)), to: nil, from: nil)
                }

                Button("Table") {
                    NSApp.sendAction(#selector(ClearlyTextView.insertMarkdownTable(_:)), to: nil, from: nil)
                }

                Divider()

                Button("Code") {
                    NSApp.sendAction(#selector(ClearlyTextView.toggleInlineCode(_:)), to: nil, from: nil)
                }

                Button("Code Block") {
                    NSApp.sendAction(#selector(ClearlyTextView.insertCodeBlock(_:)), to: nil, from: nil)
                }

                Divider()

                Button("Math") {
                    NSApp.sendAction(#selector(ClearlyTextView.toggleInlineMath(_:)), to: nil, from: nil)
                }

                Button("Math Block") {
                    NSApp.sendAction(#selector(ClearlyTextView.insertMathBlock(_:)), to: nil, from: nil)
                }

                Divider()

                Button("Page Break") {
                    NSApp.sendAction(#selector(ClearlyTextView.insertPageBreak(_:)), to: nil, from: nil)
                }
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

// MARK: - Export / Print Commands

struct ExportPDFCommand: View {
    @FocusedValue(\.documentText) var text
    @FocusedValue(\.documentFileURL) var fileURL
    @AppStorage("editorFontSize") private var fontSize: Double = 16

    var body: some View {
        Button("Export as PDF…") {
            guard let text else { return }
            PDFExporter().exportPDF(markdown: text, fontSize: CGFloat(fontSize), fileURL: fileURL)
        }
        .disabled(text == nil)
        .keyboardShortcut("e", modifiers: [.command, .shift])
    }
}

struct PrintCommand: View {
    @FocusedValue(\.documentText) var text
    @FocusedValue(\.documentFileURL) var fileURL
    @AppStorage("editorFontSize") private var fontSize: Double = 16

    var body: some View {
        Button("Print…") {
            guard let text else { return }
            PDFExporter().printHTML(markdown: text, fontSize: CGFloat(fontSize), fileURL: fileURL)
        }
        .disabled(text == nil)
        .keyboardShortcut("p", modifiers: .command)
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
