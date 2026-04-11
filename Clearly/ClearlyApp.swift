import SwiftUI
#if canImport(Sparkle)
import Sparkle
#endif

func activateDocumentApp() {
    if NSApp.activationPolicy() != .regular {
        NSApp.setActivationPolicy(.regular)
    }
    // Document opens from the menu bar must steal focus from the current app.
    NSApp.activate(ignoringOtherApps: true)
}

@MainActor
final class WindowRouter {
    static let shared = WindowRouter()
    static let sceneID = "main"
    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("ClearlyMainWindow")
    private static let openRetryCount = 5
    private static let openRetryDelay: TimeInterval = 0.05

    var openMainWindow: (() -> Void)?

    func showMainWindow() {
        activateDocumentApp()

        if let window = visibleDocumentWindows().first {
            present(window)
            return
        }

        openMainWindow?()

        presentOpenedMainWindow(retriesRemaining: Self.openRetryCount)
    }

    private func present(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func presentOpenedMainWindow(retriesRemaining: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.openRetryDelay) { [weak self] in
            guard let self else { return }
            if let window = self.visibleDocumentWindows().first {
                self.present(window)
                return
            }
            guard retriesRemaining > 0 else { return }
            self.presentOpenedMainWindow(retriesRemaining: retriesRemaining - 1)
        }
    }

    private func visibleDocumentWindows() -> [NSWindow] {
        NSApp.windows.filter { Self.isVisibleMainDocumentWindow($0) }
    }

    static func isUserFacingDocumentWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel), !window.isSheet, window.level != .floating else { return false }
        return window.frame.width >= 50 && window.frame.height >= 50
    }

    static func isVisibleUserFacingDocumentWindow(_ window: NSWindow) -> Bool {
        isUserFacingDocumentWindow(window) && (window.isVisible || window.isMiniaturized)
    }

    static func isMainDocumentWindow(_ window: NSWindow) -> Bool {
        window.identifier == Self.mainWindowIdentifier && isUserFacingDocumentWindow(window)
    }

    static func isVisibleMainDocumentWindow(_ window: NSWindow) -> Bool {
        isMainDocumentWindow(window) && (window.isVisible || window.isMiniaturized)
    }
}

struct MainWindowBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MainWindowMarker()
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onAppear {
                WindowRouter.shared.openMainWindow = { openWindow(id: WindowRouter.sceneID) }
            }
    }
}

struct MainWindowMarker: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.identifier = WindowRouter.mainWindowIdentifier
            context.coordinator.attach(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.identifier = WindowRouter.mainWindowIdentifier
            context.coordinator.attach(to: nsView.window)
        }
    }

    final class Coordinator {
        private let delegate = WindowDelegate()
        private weak var window: NSWindow?

        func attach(to window: NSWindow?) {
            guard let window else { return }
            guard self.window !== window else { return }
            self.window = window
            window.delegate = delegate
        }
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard let appDelegate = NSApp.delegate as? ClearlyAppDelegate else { return true }
            return appDelegate.shouldCloseMainWindow(sender)
        }
    }
}

// MARK: - App Delegate (dock icon management + file open handling)

@MainActor
final class ClearlyAppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [Any] = []
    private var commandQMonitor: Any?
    private var showHiddenFilesMonitor: Any?
    private var isProgrammaticallyClosingWindows = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A normal Launch Services open activates the app and opens a document window.
        // Login-item launch stays inactive with no document windows, so collapse to
        // menubar-only only in that state instead of guessing from parent PID.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if !NSApp.isActive && !self.hasDocumentWindows() {
                NSApp.setActivationPolicy(.accessory)
            }
        }

        // Watch multiple signals — window close, app deactivate, main window change
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.updateActivationPolicy() }
        })
        observers.append(nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.updateActivationPolicy() }
        })
        observers.append(nc.addObserver(forName: NSWindow.didResignMainNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.updateActivationPolicy() }
        })
        observers.append(nc.addObserver(forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { notification in
            Task { @MainActor in
                guard let window = notification.object as? NSWindow else { return }
                guard WindowRouter.isUserFacingDocumentWindow(window) else { return }
                activateDocumentApp()
                window.orderFrontRegardless()
            }
        })

        commandQMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.shouldCloseToMenuBar(for: event) else { return event }
            self.closeDocumentWindowsToMenuBar()
            return nil
        }

        showHiddenFilesMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.shouldToggleHiddenFiles(for: event) else { return event }
            WorkspaceManager.shared.toggleShowHiddenFiles()
            return nil
        }

    }

    // MARK: - Open files from Finder

    func application(_ application: NSApplication, open urls: [URL]) {
        let workspace = WorkspaceManager.shared
        var openedDirectory = false
        var openedFile = false
        for url in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                openedDirectory = true
                if !workspace.locations.contains(where: { $0.url == url }) {
                    workspace.addLocation(url: url)
                }
            } else {
                openedFile = workspace.openFile(at: url) || openedFile
            }
        }
        if openedDirectory {
            workspace.isSidebarVisible = true
            UserDefaults.standard.set(true, forKey: "sidebarVisible")
        }
        if openedDirectory || openedFile {
            WindowRouter.shared.showMainWindow()
        } else {
            activateDocumentApp()
        }
    }

    // MARK: - Prevent default new window on reactivation

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            WindowRouter.shared.showMainWindow()
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        WorkspaceManager.shared.prepareForAppTermination() ? .terminateNow : .terminateCancel
    }

    // MARK: - Save on termination

    func applicationWillTerminate(_ notification: Notification) {
        if let commandQMonitor {
            NSEvent.removeMonitor(commandQMonitor)
            self.commandQMonitor = nil
        }
        if let showHiddenFilesMonitor {
            NSEvent.removeMonitor(showHiddenFilesMonitor)
            self.showHiddenFilesMonitor = nil
        }
    }

    // MARK: - Spelling and Grammar menu injection

    /// SwiftUI owns the Edit menu and regenerates its items on every update cycle.
    /// `applicationWillUpdate` fires on every run-loop iteration just before the
    /// UI refreshes, so we can re-inject our submenu after SwiftUI wipes it.
    /// The guard on `contains(where:)` makes this a no-op in the common case.
    func applicationWillUpdate(_ notification: Notification) {
        injectSpellingMenuIfNeeded()
    }

    private func injectSpellingMenuIfNeeded() {
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

        // Place before Writing Tools (and its preceding separator) if present.
        if let writingToolsIndex = editMenu.items.firstIndex(where: { $0.title == "Writing Tools" }) {
            // Insert before the separator that precedes Writing Tools
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

    func applicationWillBecomeActive(_ notification: Notification) {
        if hasDocumentWindows() && NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    func closeDocumentWindowsToMenuBar() {
        guard WorkspaceManager.shared.prepareForWindowClose() else { return }
        let documentWindows = NSApp.windows.filter { WindowRouter.isVisibleUserFacingDocumentWindow($0) }

        isProgrammaticallyClosingWindows = true
        for window in documentWindows {
            window.performClose(nil)
        }
        isProgrammaticallyClosingWindows = false

        Task { @MainActor in ScratchpadManager.shared.closeAll() }
        updateActivationPolicy()
    }

    func shouldCloseMainWindow(_ window: NSWindow) -> Bool {
        if isProgrammaticallyClosingWindows {
            return true
        }
        return WorkspaceManager.shared.prepareForWindowClose()
    }

    private func updateActivationPolicy() {
        if hasDocumentWindows() {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
        } else {
            if NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    /// A "document window" is any user-facing window that isn't a scratchpad,
    /// MenuBarExtra panel, sheet, or internal SwiftUI bookkeeping window.
    private func hasDocumentWindows() -> Bool {
        NSApp.windows.contains { WindowRouter.isVisibleUserFacingDocumentWindow($0) }
    }

    func shouldCloseToMenuBar(for event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard event.charactersIgnoringModifiers?.lowercased() == "q" else { return false }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return modifiers == [.command]
    }

    func shouldToggleHiddenFiles(for event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        // keyCode 47 = period key; charactersIgnoringModifiers gives ">" when Shift is held
        guard event.keyCode == 47 else { return false }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == [.command, .shift] else { return false }

        guard let window = event.window else { return false }
        guard WindowRouter.isMainDocumentWindow(window) else { return false }

        return true
    }
}

// MARK: - Main View (NavigationSplitView: sidebar + detail)

struct MainView: View {
    @Bindable var workspace: WorkspaceManager
    @State private var columnVisibility: NavigationSplitViewVisibility

    init(workspace: WorkspaceManager) {
        self.workspace = workspace
        _columnVisibility = State(initialValue: workspace.isSidebarVisible ? .all : .detailOnly)
    }

    private var windowTitle: String {
        if let doc = workspace.openDocuments.first(where: { $0.id == workspace.activeDocumentID }) {
            return doc.displayName
        }
        return "Clearly"
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            FileExplorerView(workspace: workspace)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            if workspace.activeDocumentID != nil {
                ContentView(workspace: workspace)
            } else {
                NoFileView(workspace: workspace)
            }
        }
        .navigationTitle(windowTitle)
        .onChange(of: columnVisibility) { _, newValue in
            let visible = (newValue != .detailOnly)
            workspace.isSidebarVisible = visible
            UserDefaults.standard.set(visible, forKey: "sidebarVisible")
        }
        .onChange(of: workspace.isSidebarVisible) { _, visible in
            withAnimation {
                columnVisibility = visible ? .all : .detailOnly
            }
        }
    }
}

// MARK: - Empty State (no file open)

struct NoFileView: View {
    var workspace: WorkspaceManager

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No File Open")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Create a new document with ⌘N or open a file with ⌘O")
                .font(.body)
                .foregroundStyle(.tertiary)
            HStack(spacing: 12) {
                Button("New Document") {
                    workspace.createUntitledDocument()
                }
                .keyboardShortcut(.defaultAction)
                Button("Open…") {
                    workspace.showOpenPanel()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundColorSwiftUI)
    }
}

@main
struct ClearlyApp: App {
    @NSApplicationDelegateAdaptor(ClearlyAppDelegate.self) var appDelegate
    @AppStorage("themePreference") private var themePreference = "system"
    @State private var scratchpadManager = ScratchpadManager.shared
    private let workspace = WorkspaceManager.shared
    #if canImport(Sparkle)
    private let updaterController: SPUStandardUpdaterController
    #endif

    init() {
        DiagnosticLog.trimIfNeeded()
        DiagnosticLog.log("App launched")
        #if canImport(Sparkle)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
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
        Window("Clearly", id: WindowRouter.sceneID) {
            MainView(workspace: workspace)
                .preferredColorScheme(resolvedColorScheme)
                .background(MainWindowBridge())
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 920, height: 900)
        .commands {
            // Replace New/Open with our own
            CommandGroup(replacing: .newItem) {
                Button("New Document") {
                    workspace.createUntitledDocument()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Open…") {
                    workspace.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            // Save
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    workspace.saveCurrentFile()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(workspace.activeDocumentID == nil)
            }

            #if canImport(Sparkle)
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            #endif
            CommandGroup(after: .importExport) {
                ExportPDFCommand()
            }
            CommandGroup(replacing: .printItem) {
                PrintCommand()
            }
            // View menu — sidebar, editor/preview modes, outline
            CommandGroup(before: .toolbar) {
                Button("Toggle Sidebar") {
                    NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                ViewModeCommands()

                Divider()

                OutlineToggleCommand()

                Divider()

                Button(workspace.showHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files") {
                    workspace.toggleShowHiddenFiles()
                }
            }

            CommandGroup(after: .textEditing) {
                FindCommand()
            }
            CommandGroup(after: .textFormatting) {
                FontSizeCommands()
            }
            CommandGroup(replacing: .help) {
                Button("Clearly Help") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Shpigford/clearly/issues")!)
                }
                Divider()
                Button("Sample Document") {
                    if let url = Bundle.main.url(forResource: "demo", withExtension: "md"),
                       let content = try? String(contentsOf: url, encoding: .utf8) {
                        workspace.createDocumentWithContent(content)
                    }
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
            #if canImport(Sparkle)
            SettingsView(updater: updaterController.updater)
                .preferredColorScheme(resolvedColorScheme)
            #else
            SettingsView()
                .preferredColorScheme(resolvedColorScheme)
            #endif
        }

        MenuBarExtra("Scratchpads", image: "ScratchpadMenuBarIcon") {
            ScratchpadMenuBar(manager: scratchpadManager)
        }
    }

}

struct FindCommand: View {
    @FocusedValue(\.findState) var findState

    var body: some View {
        Button("Find…") {
            findState?.present()
        }
        .keyboardShortcut("f", modifiers: .command)
    }
}

struct OutlineToggleCommand: View {
    @FocusedValue(\.outlineState) var outlineState

    var body: some View {
        Button("Toggle Outline") {
            outlineState?.toggle()
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
    }
}

struct ViewModeCommands: View {
    @FocusedValue(\.viewMode) var mode

    var body: some View {
        Button("Editor") {
            mode?.wrappedValue = .edit
        }
        .keyboardShortcut("1", modifiers: .command)

        Button("Preview") {
            mode?.wrappedValue = .preview
        }
        .keyboardShortcut("2", modifiers: .command)
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
#endif

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

#if canImport(Sparkle)
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
#endif
