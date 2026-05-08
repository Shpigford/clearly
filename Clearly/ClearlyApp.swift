import AppKit
import SwiftUI
import UniformTypeIdentifiers
import KeyboardShortcuts
import ClearlyCore
#if canImport(Sparkle)
import Sparkle
#endif

// MARK: - App Delegate

@MainActor
final class ClearlyAppDelegate: NSObject, NSApplicationDelegate {
    static private(set) weak var shared: ClearlyAppDelegate?

    private weak var trackedSettingsWindow: NSWindow?
    private var isOpeningSettingsFromMenuBar = false
    private var observers: [Any] = []

    /// Mirrors the `@AppStorage("showMenuBarIcon")` value the SwiftUI side reads.
    /// Reads via `object(forKey:)` so the unset state resolves to `true`.
    private var showMenuBarIcon: Bool {
        (UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool) ?? true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        injectSpellingMenu()
        injectFontSubmenu()

        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let window = notification.object as? NSWindow {
                    self.clearTrackedSettingsWindow(window)
                }
            }
        })
    }

    /// Honor the user's `launchBehavior` preference. Returning `true` tells
    /// `NSDocumentController` we handled launch ourselves; returning `false`
    /// hands off to its native "Recent Files / New Document" panel — which
    /// has its own `New Document` button that dismisses cleanly.
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        switch launchBehavior {
        case "newDocument":
            do { try NSDocumentController.shared.openUntitledDocumentAndDisplay(true) }
            catch { return false }
            return true
        case "lastFile":
            if let url = NSDocumentController.shared.recentDocumentURLs.first,
               FileManager.default.fileExists(atPath: url.path) {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                return true
            }
            do { try NSDocumentController.shared.openUntitledDocumentAndDisplay(true) }
            catch { return false }
            return true
        case "nothing":
            // Claim we handled it so the system doesn't show its own panel.
            return true
        default:
            // "filePicker" — let `NSDocumentController` show the native
            // Recent Files / New Document panel.
            return false
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !hasDocumentWindows() {
            if launchBehavior == "filePicker" {
                NSDocumentController.shared.openDocument(nil)
            } else {
                _ = applicationOpenUntitledFile(sender)
            }
        }
        return true
    }

    private var launchBehavior: String {
        UserDefaults.standard.string(forKey: "launchBehavior") ?? "filePicker"
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !showMenuBarIcon
    }

    func applicationWillTerminate(_ notification: Notification) {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func hasDocumentWindows() -> Bool {
        NSApp.windows.contains { window in
            guard !(window is NSPanel), !window.isSheet, window.level != .floating else { return false }
            return window.frame.width >= 200 && window.frame.height >= 200 && window !== trackedSettingsWindow
        }
    }

    // MARK: - Settings window tracking (menu-bar Settings… coordination)

    func prepareForMenuBarSettingsActivation() {
        isOpeningSettingsFromMenuBar = true
    }

    func registerSettingsWindow(_ window: NSWindow) {
        trackedSettingsWindow = window
        isOpeningSettingsFromMenuBar = false
    }

    func clearTrackedSettingsWindow(_ window: NSWindow) {
        if trackedSettingsWindow === window {
            trackedSettingsWindow = nil
        }
        isOpeningSettingsFromMenuBar = false
    }

    // MARK: - AppKit menu injection

    /// Spelling / grammar submenu under Edit. SwiftUI's default Edit menu
    /// doesn't include this — but `NSTextView` selectors expect it.
    private func injectSpellingMenu() {
        guard let editMenu = NSApp.mainMenu?.item(withTitle: "Edit")?.submenu else { return }
        guard !editMenu.items.contains(where: { $0.title == "Spelling and Grammar" }) else { return }

        let spellingItem = NSMenuItem(title: "Spelling and Grammar", action: nil, keyEquivalent: "")
        let spellingMenu = NSMenu(title: "Spelling and Grammar")
        let showItem = NSMenuItem(title: "Show Spelling and Grammar", action: #selector(NSText.showGuessPanel(_:)), keyEquivalent: ":")
        showItem.keyEquivalentModifierMask = [.command]
        spellingMenu.addItem(showItem)
        let checkItem = NSMenuItem(title: "Check Document Now", action: #selector(NSText.checkSpelling(_:)), keyEquivalent: ";")
        checkItem.keyEquivalentModifierMask = [.command]
        spellingMenu.addItem(checkItem)
        spellingMenu.addItem(.separator())
        spellingMenu.addItem(NSMenuItem(title: "Check Spelling While Typing", action: #selector(NSTextView.toggleContinuousSpellChecking(_:)), keyEquivalent: ""))
        spellingMenu.addItem(NSMenuItem(title: "Check Grammar With Spelling", action: #selector(NSTextView.toggleGrammarChecking(_:)), keyEquivalent: ""))
        spellingMenu.addItem(NSMenuItem(title: "Correct Spelling Automatically", action: #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)), keyEquivalent: ""))
        spellingItem.submenu = spellingMenu

        if let writingToolsIndex = editMenu.items.firstIndex(where: { $0.title == "Writing Tools" }) {
            let insertIndex = (writingToolsIndex > 0 && editMenu.items[writingToolsIndex - 1].isSeparatorItem)
                ? writingToolsIndex - 1
                : writingToolsIndex
            editMenu.insertItem(spellingItem, at: insertIndex)
            editMenu.insertItem(.separator(), at: insertIndex)
        } else {
            editMenu.addItem(.separator())
            editMenu.addItem(spellingItem)
        }
    }

    /// Preview Font submenu under View.
    private func injectFontSubmenu() {
        guard let viewMenu = NSApp.mainMenu?.item(withTitle: "View")?.submenu else { return }
        guard !viewMenu.items.contains(where: { $0.title == "Preview Font" }) else { return }

        let fontSubmenu = NSMenu(title: "Preview Font")
        for (title, value) in [("San Francisco", "sanFrancisco"), ("New York", "newYork"), ("SF Mono", "sfMono")] {
            let item = NSMenuItem(title: title, action: #selector(setPreviewFontAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            fontSubmenu.addItem(item)
        }
        let fontMenuItem = NSMenuItem(title: "Preview Font", action: nil, keyEquivalent: "")
        fontMenuItem.submenu = fontSubmenu
        viewMenu.addItem(.separator())
        viewMenu.addItem(fontMenuItem)
    }

    @objc private func setPreviewFontAction(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        UserDefaults.standard.set(value, forKey: "previewFontFamily")
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(setPreviewFontAction(_:)) {
            let current = UserDefaults.standard.string(forKey: "previewFontFamily") ?? "sanFrancisco"
            menuItem.state = (menuItem.representedObject as? String) == current ? .on : .off
            return true
        }
        return true
    }
}

// MARK: - App Entry

@main
struct ClearlyApp: App {
    @NSApplicationDelegateAdaptor(ClearlyAppDelegate.self) var appDelegate
    @AppStorage("themePreference") private var themePreference = "system"
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @State private var scratchpadManager = ScratchpadManager.shared

    #if canImport(Sparkle)
    private let updaterController: SPUStandardUpdaterController
    #endif

    init() {
        DiagnosticLog.trimIfNeeded()
        DiagnosticLog.log("App launched")
        #if canImport(Sparkle)
        #if DEBUG
        updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        #else
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
        #endif
    }

    private var resolvedColorScheme: ColorScheme? {
        switch themePreference {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
                .preferredColorScheme(resolvedColorScheme)
        }
        .defaultSize(width: 800, height: 900)
        .commands {
            CommandGroup(after: .appInfo) {
                #if canImport(Sparkle)
                CheckForUpdatesView(updater: updaterController.updater)
                #endif
            }
            CommandGroup(replacing: .printItem) {
                ExportPrintCommands()
            }
            CommandGroup(after: .textEditing) {
                FindCommand()
            }
            CommandGroup(after: .toolbar) {
                ViewModeCommands()
                OutlineToggleCommand()
                StatusBarToggleCommand()
                LineNumbersToggleCommand()
            }
            CommandGroup(replacing: .textFormatting) {
                FontSizeCommands()
                Divider()
                Button("Bold") { performFormattingCommand(selector: #selector(ClearlyTextView.toggleBold(_:))) }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Italic") { performFormattingCommand(selector: #selector(ClearlyTextView.toggleItalic(_:))) }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Strikethrough") { performFormattingCommand(selector: #selector(ClearlyTextView.toggleStrikethrough(_:))) }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
                Button("Heading") { performFormattingCommand(selector: #selector(ClearlyTextView.insertHeading(_:))) }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Divider()
                Button("Link…") { performFormattingCommand(selector: #selector(ClearlyTextView.insertLink(_:))) }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Image…") { performFormattingCommand(selector: #selector(ClearlyTextView.insertImage(_:))) }
                Divider()
                Button("Bullet List") { performFormattingCommand(selector: #selector(ClearlyTextView.toggleBulletList(_:))) }
                Button("Numbered List") { performFormattingCommand(selector: #selector(ClearlyTextView.toggleNumberedList(_:))) }
                Button("Todo") { performFormattingCommand(selector: #selector(ClearlyTextView.toggleTodoList(_:))) }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Divider()
                Button("Quote") { performFormattingCommand(selector: #selector(ClearlyTextView.toggleBlockquote(_:))) }
                Button("Horizontal Rule") { performFormattingCommand(selector: #selector(ClearlyTextView.insertHorizontalRule(_:))) }
                Button("Table") { performFormattingCommand(selector: #selector(ClearlyTextView.insertMarkdownTable(_:))) }
                Divider()
                Button("Code") { performFormattingCommand(selector: #selector(ClearlyTextView.toggleInlineCode(_:))) }
                Button("Code Block") { performFormattingCommand(selector: #selector(ClearlyTextView.insertCodeBlock(_:))) }
                Divider()
                Button("Math") { performFormattingCommand(selector: #selector(ClearlyTextView.toggleInlineMath(_:))) }
                Button("Math Block") { performFormattingCommand(selector: #selector(ClearlyTextView.insertMathBlock(_:))) }
                Divider()
                Button("Page Break") { performFormattingCommand(selector: #selector(ClearlyTextView.insertPageBreak(_:))) }
            }
            CommandGroup(replacing: .help) {
                Button("Clearly Help") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Shpigford/clearly/issues")!)
                }
                Button("Report a Bug…") {
                    let version = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"
                    let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
                    let url = BugReportURL.build(
                        platform: .macOS,
                        appVersion: "\(version) (\(build))",
                        osVersion: ProcessInfo.processInfo.operatingSystemVersionString
                    )
                    NSWorkspace.shared.open(url)
                }
                Button("What's New…") {
                    NSWorkspace.shared.open(URL(string: "https://clearly.md/changelog")!)
                }
                Divider()
                Button("Sample Document") {
                    openSampleDocument()
                }
                Divider()
                Button("Export Diagnostic Log…") {
                    do {
                        let logText = try DiagnosticLog.exportRecentLogs()
                        let panel = NSSavePanel()
                        panel.allowedContentTypes = [.plainText]
                        panel.nameFieldStringValue = "Clearly-Diagnostic-Log.txt"
                        guard panel.runModal() == .OK, let url = panel.url else { return }
                        try logText.write(to: url, atomically: true, encoding: .utf8)
                    } catch {
                        let alert = NSAlert(error: error)
                        alert.runModal()
                    }
                }
            }
        }

        Settings {
            #if canImport(Sparkle)
            SettingsView(updater: updaterController.updater)
                .preferredColorScheme(resolvedColorScheme)
            #else
            SettingsView()
                .preferredColorScheme(resolvedColorScheme)
            #endif
        }

        MenuBarExtra("Scratchpads", image: "ScratchpadMenuBarIcon", isInserted: $showMenuBarIcon) {
            ScratchpadMenuBar(manager: scratchpadManager)
        }
    }

    /// Copies the bundled sample doc into a temp file and opens it as a new
    /// document. The temp copy avoids overwriting the bundle resource.
    private func openSampleDocument() {
        guard let url = Bundle.main.url(forResource: "demo", withExtension: "md") else { return }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Sample Document.md")
        try? FileManager.default.removeItem(at: tempURL)
        try? FileManager.default.copyItem(at: url, to: tempURL)
        NSDocumentController.shared.openDocument(withContentsOf: tempURL, display: true) { _, _, _ in }
    }
}

// MARK: - Settings window registration

struct SettingsWindowObserver: NSViewRepresentable {
    final class Holder {
        weak var window: NSWindow?
    }

    func makeCoordinator() -> Holder { Holder() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        registerWindow(from: view, context: context)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        registerWindow(from: nsView, context: context)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Holder) {
        guard let window = coordinator.window else { return }
        ClearlyAppDelegate.shared?.clearTrackedSettingsWindow(window)
    }

    private func registerWindow(from view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            context.coordinator.window = window
            ClearlyAppDelegate.shared?.registerSettingsWindow(window)
        }
    }
}

// MARK: - Focused-value keys (per-document menu binding)

private struct FindStateKey: FocusedValueKey {
    typealias Value = FindState
}

private struct OutlineStateKey: FocusedValueKey {
    typealias Value = OutlineState
}

private struct StatusBarStateKey: FocusedValueKey {
    typealias Value = StatusBarState
}

private struct ViewModeKey: FocusedValueKey {
    typealias Value = Binding<ViewMode>
}

private struct ExportPDFActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct PrintDocumentActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var findState: FindState? {
        get { self[FindStateKey.self] }
        set { self[FindStateKey.self] = newValue }
    }
    var outlineState: OutlineState? {
        get { self[OutlineStateKey.self] }
        set { self[OutlineStateKey.self] = newValue }
    }
    var statusBarState: StatusBarState? {
        get { self[StatusBarStateKey.self] }
        set { self[StatusBarStateKey.self] = newValue }
    }
    var viewMode: Binding<ViewMode>? {
        get { self[ViewModeKey.self] }
        set { self[ViewModeKey.self] = newValue }
    }
    var exportPDFAction: (() -> Void)? {
        get { self[ExportPDFActionKey.self] }
        set { self[ExportPDFActionKey.self] = newValue }
    }
    var printDocumentAction: (() -> Void)? {
        get { self[PrintDocumentActionKey.self] }
        set { self[PrintDocumentActionKey.self] = newValue }
    }
}

// MARK: - Per-document command views

struct ExportPrintCommands: View {
    @FocusedValue(\.exportPDFAction) var exportPDFAction
    @FocusedValue(\.printDocumentAction) var printDocumentAction

    var body: some View {
        Button("Export as PDF…") {
            exportPDFAction?()
        }
        .keyboardShortcut("e", modifiers: [.command, .shift])
        .disabled(exportPDFAction == nil)

        Button("Print…") {
            printDocumentAction?()
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])
        .disabled(printDocumentAction == nil)
    }
}

struct FindCommand: View {
    @FocusedValue(\.findState) var findState

    var body: some View {
        Button("Find…") {
            findState?.toggle()
        }
        .keyboardShortcut("f", modifiers: .command)
        .disabled(findState == nil)
    }
}

struct OutlineToggleCommand: View {
    @FocusedValue(\.outlineState) var outlineState

    var body: some View {
        Button {
            outlineState?.isVisible.toggle()
        } label: {
            Label("Toggle Outline", systemImage: "list.bullet.indent")
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
        .disabled(outlineState == nil)
    }
}

struct StatusBarToggleCommand: View {
    @FocusedValue(\.statusBarState) var statusBarState

    var body: some View {
        Button {
            statusBarState?.toggle()
        } label: {
            Label(
                statusBarState?.isVisible == true ? "Hide Word Counts" : "Show Word Counts",
                systemImage: "character.textbox"
            )
        }
        .disabled(statusBarState == nil)
    }
}

struct LineNumbersToggleCommand: View {
    @AppStorage("showLineNumbers") private var showLineNumbers = false

    var body: some View {
        Button {
            showLineNumbers.toggle()
        } label: {
            Label(
                showLineNumbers ? "Hide Line Numbers" : "Show Line Numbers",
                systemImage: "number"
            )
        }
    }
}

struct ViewModeCommands: View {
    @FocusedValue(\.viewMode) var mode

    var body: some View {
        Button {
            mode?.wrappedValue = .edit
        } label: {
            Label("Editor", systemImage: "square.and.pencil")
        }
        .keyboardShortcut("1", modifiers: .command)
        .disabled(mode == nil)

        Button {
            mode?.wrappedValue = .preview
        } label: {
            Label("Preview", systemImage: "eye")
        }
        .keyboardShortcut("2", modifiers: .command)
        .disabled(mode == nil)
    }
}

struct FontSizeCommands: View {
    @AppStorage("editorFontSize") private var fontSize: Double = 12

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

@MainActor
func performFormattingCommand(selector: Selector) {
    NSApp.sendAction(selector, to: nil, from: nil)
}

// MARK: - Sparkle Check for Updates menu item

#if canImport(Sparkle)
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
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            DispatchQueue.main.async {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }
}
#endif
