import SwiftUI
#if canImport(Sparkle)
import Sparkle
#endif

private var trafficLightConstraintsInstalled = false

func repositionTrafficLights(in window: NSWindow) {
    guard !trafficLightConstraintsInstalled else { return }
    guard let closeButton = window.standardWindowButton(.closeButton),
          let minimizeButton = window.standardWindowButton(.miniaturizeButton),
          let zoomButton = window.standardWindowButton(.zoomButton),
          let titlebarView = closeButton.superview else { return }

    let buttons = [closeButton, minimizeButton, zoomButton]
    let xPositions: [CGFloat] = [14, 34, 54]
    let topInset: CGFloat = 14

    for (button, xPos) in zip(buttons, xPositions) {
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: titlebarView.leadingAnchor, constant: xPos),
            button.topAnchor.constraint(equalTo: titlebarView.topAnchor, constant: topInset),
        ])
    }

    trafficLightConstraintsInstalled = true
}

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
    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("ClearlyMainWindow")
    static let launcherWindowIdentifier = NSUserInterfaceItemIdentifier("ClearlyLauncherWindow")

    func showMainWindow() {
        activateDocumentApp()

        if let window = visibleDocumentWindows().first {
            present(window)
            return
        }

        if let appDelegate = NSApp.delegate as? ClearlyAppDelegate {
            appDelegate.createMainWindow()
        }
    }

    private func present(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func visibleDocumentWindows() -> [NSWindow] {
        NSApp.windows.filter { Self.isVisibleMainDocumentWindow($0) }
    }

    static func isUserFacingDocumentWindow(_ window: NSWindow) -> Bool {
        guard window.identifier != Self.launcherWindowIdentifier else { return false }
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

struct LauncherSceneMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window)
        }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.identifier = WindowRouter.launcherWindowIdentifier
        window.isExcludedFromWindowsMenu = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.setContentSize(NSSize(width: 1, height: 1))
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderOut(nil)

        guard let appDelegate = NSApp.delegate as? ClearlyAppDelegate else { return }
        appDelegate.ensureMainWindowIfNeeded()
    }
}

// MARK: - App Delegate (dock icon management + file open handling)

@MainActor
final class ClearlyAppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var observers: [Any] = []
    private var commandQMonitor: Any?
    private var showHiddenFilesMonitor: Any?
    private var sidebarToggleMonitor: Any?
    private var quickSwitcherMonitor: Any?
    private var themeObserver: Any?
    private var languageObserver: Any?
    private var isProgrammaticallyClosingWindows = false
    private(set) var mainWindow: NSWindow?

    private(set) var splitViewController: ClearlySplitViewController?

    func createMainWindow() {
        guard mainWindow == nil else {
            mainWindow?.makeKeyAndOrderFront(nil)
            return
        }

        let workspace = WorkspaceManager.shared

        // Build the split view controller (AppKit, like Things/Bear/Mail)
        let splitVC = ClearlySplitViewController(workspace: workspace)
        self.splitViewController = splitVC

        let window = NSWindow(contentViewController: splitVC)
        window.identifier = WindowRouter.mainWindowIdentifier
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 600, height: 400)
        window.setContentSize(NSSize(width: 960, height: 900))
        window.center()
        window.setFrameAutosaveName("ClearlyMainWindow")

        // Empty toolbar triggers macOS 26's larger ~26pt corner radius
        let toolbar = NSToolbar(identifier: "ClearlyMainToolbar")
        toolbar.showsBaselineSeparator = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        let themePreference = UserDefaults.standard.string(forKey: "themePreference") ?? "system"
        let appearance: NSAppearance? = switch themePreference {
            case "light": NSAppearance(named: .aqua)
            case "dark": NSAppearance(named: .darkAqua)
            default: nil
        }
        window.appearance = appearance
        window.delegate = mainWindowDelegate

        self.mainWindow = window
        window.makeKeyAndOrderFront(nil)

        // Observe theme preference changes
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
        }
        themeObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateWindowAppearance()
            }
        }

        // Listen for tag filter requests (from sidebar tag clicks and preview tag links)
        NotificationCenter.default.addObserver(
            forName: .init("ClearlyFilterByTag"), object: nil, queue: .main
        ) { notification in
            guard let tag = notification.userInfo?["tag"] as? String else { return }
            Task { @MainActor in
                QuickSwitcherManager.shared.show(tagFilter: tag)
            }
        }
    }

    private func installMCPHelperIfNeeded() {
        #if canImport(Sparkle)
        guard let source = Bundle.main.url(forResource: "ClearlyMCP", withExtension: nil, subdirectory: "Helpers") else { return }
        let installDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Clearly")
        let installed = installDir.appendingPathComponent("ClearlyMCP")

        try? FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        let shouldCopy = !FileManager.default.fileExists(atPath: installed.path)
            || (try? Data(contentsOf: source)) != (try? Data(contentsOf: installed))

        if shouldCopy {
            try? FileManager.default.removeItem(at: installed)
            try? FileManager.default.copyItem(at: source, to: installed)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installed.path)
        }
        #endif
    }

    private func updateWindowAppearance() {
        guard let window = mainWindow else { return }
        let pref = UserDefaults.standard.string(forKey: "themePreference") ?? "system"
        let appearance: NSAppearance? = switch pref {
            case "light": NSAppearance(named: .aqua)
            case "dark": NSAppearance(named: .darkAqua)
            default: nil
        }
        window.appearance = appearance
    }

    private let mainWindowDelegate = MainWindowDelegateImpl()

    private class MainWindowDelegateImpl: NSObject, NSWindowDelegate {
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard let appDelegate = NSApp.delegate as? ClearlyAppDelegate else { return true }
            return appDelegate.shouldCloseMainWindow(sender)
        }

        func windowWillClose(_ notification: Notification) {
            guard let appDelegate = NSApp.delegate as? ClearlyAppDelegate else { return }
            if let window = notification.object as? NSWindow, window === appDelegate.mainWindow {
                appDelegate.handleMainWindowWillClose()
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMCPHelperIfNeeded()

        // A normal Launch Services open activates the app and opens a document window.
        // Login-item launch stays inactive with no document windows, so collapse to
        // menubar-only only in that state instead of guessing from parent PID.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if !NSApp.isActive && !self.hasDocumentWindows() {
                NSApp.setActivationPolicy(.accessory)
            }
        }

        // Active launches should open the main window. Background/login-item launches should not.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.isForegroundActivation else { return }
            self.createMainWindow()
        }

        // Watch multiple signals — window close, app deactivate, main window change
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let window = notification.object as? NSWindow, window === self.mainWindow {
                    self.handleMainWindowWillClose()
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.updateActivationPolicy()
                }
            }
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

        languageObserver = nc.addObserver(forName: .appLanguageDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLocalizedUI()
            }
        }

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

        // Cmd+Shift+L toggles sidebar, Cmd+1/2 switches mode, Cmd+Shift+O toggles outline
        sidebarToggleMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.type == .keyDown else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

            if chars == "l" && mods == [.command, .shift] {
                self.doToggleSidebar()
                return nil
            }
            if chars == "1" && mods == [.command] {
                NotificationCenter.default.post(name: .init("ClearlySetViewMode"), object: "edit")
                return nil
            }
            if chars == "2" && mods == [.command] {
                NotificationCenter.default.post(name: .init("ClearlySetViewMode"), object: "preview")
                return nil
            }
            if chars == "o" && mods == [.command, .shift] {
                NotificationCenter.default.post(name: .init("ClearlyToggleOutline"), object: nil)
                return nil
            }
            if chars == "b" && mods == [.command, .shift] {
                NotificationCenter.default.post(name: .init("ClearlyToggleBacklinks"), object: nil)
                return nil
            }
            if chars == "f" && mods == [.command, .shift] {
                QuickSwitcherManager.shared.toggle()
                return nil
            }
            return event
        }

        quickSwitcherMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if chars == "p" && mods == [.command] {
                QuickSwitcherManager.shared.toggle()
                return nil
            }
            return event
        }

        // Inject Quick Open menu item once (View menu isn't wiped by SwiftUI)
        DispatchQueue.main.async { [weak self] in
            self?.injectQuickOpenIfNeeded()
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
            setSidebarVisible(true, animated: false)
        }
        if openedDirectory || openedFile {
            WindowRouter.shared.showMainWindow()
        } else {
            activateDocumentApp()
        }
    }

    // MARK: - Prevent default new window on reactivation

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !hasDocumentWindows() {
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
        if let sidebarToggleMonitor {
            NSEvent.removeMonitor(sidebarToggleMonitor)
            self.sidebarToggleMonitor = nil
        }
        if let quickSwitcherMonitor {
            NSEvent.removeMonitor(quickSwitcherMonitor)
            self.quickSwitcherMonitor = nil
        }
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
            self.themeObserver = nil
        }
        if let languageObserver {
            NotificationCenter.default.removeObserver(languageObserver)
            self.languageObserver = nil
        }
    }

    // MARK: - Spelling and Grammar menu injection

    /// SwiftUI owns the Edit menu and regenerates its items on every update cycle.
    /// `applicationWillUpdate` fires on every run-loop iteration just before the
    /// UI refreshes, so we can re-inject our submenu after SwiftUI wipes it.
    /// The guard on `contains(where:)` makes this a no-op in the common case.
    func applicationWillUpdate(_ notification: Notification) {
        injectSpellingMenuIfNeeded()
        injectSidebarToggleIfNeeded()
        injectViewCommandsIfNeeded()
        refreshLocalizedMenuTitles()
        refreshSwiftUICommandMenuTitles()
        injectGlobalSearchIfNeeded()
        injectExportPrintIfNeeded()
    }

    private func menuContainingAnyAction(_ selectors: [Selector]) -> NSMenu? {
        NSApp.mainMenu?.items.first { item in
            guard let submenu = item.submenu else { return false }
            return submenu.items.contains { menuItem in
                guard let action = menuItem.action else { return false }
                return selectors.contains(action)
            }
        }?.submenu
    }

    private func topLevelMenu(key: String, defaultValue: String) -> NSMenu? {
        guard let mainMenu = NSApp.mainMenu else { return nil }
        let candidates = localizationsForKey(key, defaultValue: defaultValue)
        return mainMenu.items.first(where: { candidates.contains($0.title) })?.submenu
    }

    private func fileMenu() -> NSMenu? {
        topLevelMenu(key: "app.menu.file", defaultValue: "File")
    }

    private func editMenu() -> NSMenu? {
        menuContainingAnyAction([
            #selector(NSText.copy(_:)),
            #selector(NSText.paste(_:))
        ])
    }

    private func viewMenu() -> NSMenu? {
        menuContainingAnyAction([
            #selector(NSWindow.toggleToolbarShown(_:)),
            #selector(NSWindow.toggleFullScreen(_:))
        ])
    }

    private func injectGlobalSearchIfNeeded() {
        guard let viewMenu = viewMenu() else { return }
        guard !viewMenu.items.contains(where: { $0.action == #selector(globalSearchAction(_:)) }) else { return }

        let item = NSMenuItem(
            title: L10n.string("app.menu.view.searchAllFiles", defaultValue: "Search All Files…"),
            action: #selector(globalSearchAction(_:)),
            keyEquivalent: "f"
        )
        item.keyEquivalentModifierMask = [.command, .shift]
        item.target = self

        if let quickOpenIndex = viewMenu.items.firstIndex(where: { $0.action == #selector(quickOpenAction(_:)) }) {
            viewMenu.insertItem(item, at: quickOpenIndex + 1)
        } else {
            let insertAt = min(3, viewMenu.items.count)
            viewMenu.insertItem(item, at: insertAt)
        }
    }

    @objc private func globalSearchAction(_ sender: Any?) {
        QuickSwitcherManager.shared.toggle()
    }

    private func injectSidebarToggleIfNeeded() {
        guard let viewMenu = viewMenu() else { return }
        guard !viewMenu.items.contains(where: { $0.action == #selector(toggleSidebarMenuAction(_:)) }) else { return }

        let sidebarItem = NSMenuItem(
            title: L10n.string("app.menu.view.toggleSidebar", defaultValue: "Toggle Sidebar"),
            action: #selector(toggleSidebarMenuAction(_:)),
            keyEquivalent: "l"
        )
        sidebarItem.keyEquivalentModifierMask = [.command, .shift]
        sidebarItem.target = self

        // Insert at the beginning of the View menu
        viewMenu.insertItem(sidebarItem, at: 0)
        viewMenu.insertItem(.separator(), at: 1)
    }

    @objc private func toggleSidebarMenuAction(_ sender: Any?) {
        doToggleSidebar()
    }

    private func localizationsForKey(_ key: String, defaultValue: String) -> Set<String> {
        var titles = Set([defaultValue])
        for localization in AppLanguage.supportedIdentifiers {
            titles.insert(L10n.string(key, defaultValue: defaultValue, localization: localization))
        }
        return titles
    }

    private func updateMenuTitles(
        in menu: NSMenu?,
        key: String,
        defaultValue: String,
        title: String
    ) {
        guard let menu else { return }
        let candidates = localizationsForKey(key, defaultValue: defaultValue)
        for item in menu.items where candidates.contains(item.title) {
            item.title = title
        }
        for item in menu.items {
            updateMenuTitles(in: item.submenu, key: key, defaultValue: defaultValue, title: title)
        }
    }

    private func updateTopLevelMenuTitle(
        key: String,
        defaultValue: String,
        title: String
    ) {
        guard let mainMenu = NSApp.mainMenu else { return }
        let candidates = localizationsForKey(key, defaultValue: defaultValue)
        guard let item = mainMenu.items.first(where: { candidates.contains($0.title) }) else { return }
        item.title = title
        item.submenu?.title = title
    }

    private func updateMenuItemTitle(in menu: NSMenu?, action: Selector, title: String) {
        guard let item = menu?.items.first(where: { $0.action == action }) else { return }
        item.title = title
    }

    private func refreshLocalizedMenuTitles() {
        let viewMenu = viewMenu()
        updateMenuItemTitle(
            in: viewMenu,
            action: #selector(toggleSidebarMenuAction(_:)),
            title: L10n.string("app.menu.view.toggleSidebar", defaultValue: "Toggle Sidebar")
        )
        updateMenuItemTitle(
            in: viewMenu,
            action: #selector(toggleOutlineAction(_:)),
            title: L10n.string("app.menu.toggleOutline", defaultValue: "Toggle Outline")
        )
        updateMenuItemTitle(
            in: viewMenu,
            action: #selector(toggleBacklinksAction(_:)),
            title: L10n.string("app.menu.toggleBacklinks", defaultValue: "Toggle Backlinks")
        )
        updateMenuItemTitle(
            in: viewMenu,
            action: #selector(switchToEditorAction(_:)),
            title: L10n.string("app.menu.view.editor", defaultValue: "Editor")
        )
        updateMenuItemTitle(
            in: viewMenu,
            action: #selector(switchToPreviewAction(_:)),
            title: L10n.string("app.menu.view.preview", defaultValue: "Preview")
        )
        updateMenuItemTitle(
            in: viewMenu,
            action: #selector(quickOpenAction(_:)),
            title: L10n.string("app.menu.view.quickOpen", defaultValue: "Quick Open…")
        )
        updateMenuItemTitle(
            in: viewMenu,
            action: #selector(globalSearchAction(_:)),
            title: L10n.string("app.menu.view.searchAllFiles", defaultValue: "Search All Files…")
        )

        let fileMenu = fileMenu()
        updateMenuItemTitle(
            in: fileMenu,
            action: #selector(exportPDFAction(_:)),
            title: L10n.string("app.menu.exportPdf", defaultValue: "Export as PDF…")
        )
        updateMenuItemTitle(
            in: fileMenu,
            action: #selector(printDocumentAction(_:)),
            title: L10n.string("app.menu.print", defaultValue: "Print…")
        )

        guard let editMenu = editMenu(),
              let spellingItem = editMenu.items.first(where: {
                  $0.submenu?.items.contains(where: { $0.action == #selector(NSText.checkSpelling(_:)) }) == true
              }),
              let spellingMenu = spellingItem.submenu else {
            return
        }

        let spellingTitle = L10n.string("app.menu.spellingAndGrammar", defaultValue: "Spelling and Grammar")
        spellingItem.title = spellingTitle
        spellingMenu.title = spellingTitle

        updateMenuItemTitle(
            in: spellingMenu,
            action: #selector(NSText.showGuessPanel(_:)),
            title: L10n.string("app.menu.spelling.show", defaultValue: "Show Spelling and Grammar")
        )
        updateMenuItemTitle(
            in: spellingMenu,
            action: #selector(NSText.checkSpelling(_:)),
            title: L10n.string("app.menu.spelling.checkNow", defaultValue: "Check Document Now")
        )
        updateMenuItemTitle(
            in: spellingMenu,
            action: #selector(NSTextView.toggleContinuousSpellChecking(_:)),
            title: L10n.string("app.menu.spelling.checkWhileTyping", defaultValue: "Check Spelling While Typing")
        )
        updateMenuItemTitle(
            in: spellingMenu,
            action: #selector(NSTextView.toggleGrammarChecking(_:)),
            title: L10n.string("app.menu.spelling.checkGrammar", defaultValue: "Check Grammar With Spelling")
        )
        updateMenuItemTitle(
            in: spellingMenu,
            action: #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)),
            title: L10n.string("app.menu.spelling.correctAutomatically", defaultValue: "Correct Spelling Automatically")
        )
    }

    private func injectQuickOpenIfNeeded() {
        guard let viewMenu = viewMenu() else { return }
        guard !viewMenu.items.contains(where: { $0.action == #selector(quickOpenAction(_:)) }) else { return }

        let item = NSMenuItem(
            title: L10n.string("app.menu.view.quickOpen", defaultValue: "Quick Open…"),
            action: #selector(quickOpenAction(_:)),
            keyEquivalent: "p"
        )
        item.keyEquivalentModifierMask = [.command]
        item.target = self

        // Insert after Toggle Sidebar + separator (index 2)
        let insertAt = min(2, viewMenu.items.count)
        viewMenu.insertItem(item, at: insertAt)
    }

    @objc private func quickOpenAction(_ sender: Any?) {
        QuickSwitcherManager.shared.toggle()
    }

    private func injectViewCommandsIfNeeded() {
        guard let viewMenu = viewMenu() else { return }
        guard !viewMenu.items.contains(where: { $0.action == #selector(toggleOutlineAction(_:)) }) else { return }

        let outlineItem = NSMenuItem(
            title: L10n.string("app.menu.toggleOutline", defaultValue: "Toggle Outline"),
            action: #selector(toggleOutlineAction(_:)),
            keyEquivalent: "o"
        )
        outlineItem.keyEquivalentModifierMask = [.command, .shift]
        outlineItem.target = self

        let backlinksItem = NSMenuItem(
            title: L10n.string("app.menu.toggleBacklinks", defaultValue: "Toggle Backlinks"),
            action: #selector(toggleBacklinksAction(_:)),
            keyEquivalent: "b"
        )
        backlinksItem.keyEquivalentModifierMask = [.command, .shift]
        backlinksItem.target = self

        let editorItem = NSMenuItem(
            title: L10n.string("app.menu.view.editor", defaultValue: "Editor"),
            action: #selector(switchToEditorAction(_:)),
            keyEquivalent: "1"
        )
        editorItem.keyEquivalentModifierMask = [.command]
        editorItem.target = self

        let previewItem = NSMenuItem(
            title: L10n.string("app.menu.view.preview", defaultValue: "Preview"),
            action: #selector(switchToPreviewAction(_:)),
            keyEquivalent: "2"
        )
        previewItem.keyEquivalentModifierMask = [.command]
        previewItem.target = self

        // Insert right after Toggle Sidebar (index 0)
        var insertIndex = 1
        viewMenu.insertItem(outlineItem, at: insertIndex); insertIndex += 1
        viewMenu.insertItem(backlinksItem, at: insertIndex); insertIndex += 1
        viewMenu.insertItem(.separator(), at: insertIndex); insertIndex += 1
        viewMenu.insertItem(editorItem, at: insertIndex); insertIndex += 1
        viewMenu.insertItem(previewItem, at: insertIndex)
    }

    @objc private func switchToEditorAction(_ sender: Any?) {
        NotificationCenter.default.post(name: .init("ClearlySetViewMode"), object: "edit")
    }

    @objc private func switchToPreviewAction(_ sender: Any?) {
        NotificationCenter.default.post(name: .init("ClearlySetViewMode"), object: "preview")
    }

    @objc private func toggleOutlineAction(_ sender: Any?) {
        NotificationCenter.default.post(name: .init("ClearlyToggleOutline"), object: nil)
    }

    @objc private func toggleBacklinksAction(_ sender: Any?) {
        NotificationCenter.default.post(name: .init("ClearlyToggleBacklinks"), object: nil)
    }

    private func injectSpellingMenuIfNeeded() {
        guard let editMenu = editMenu() else { return }
        guard !editMenu.items.contains(where: { $0.submenu?.items.contains(where: { $0.action == #selector(NSText.checkSpelling(_:)) }) == true }) else { return }

        let spellingTitle = L10n.string("app.menu.spellingAndGrammar", defaultValue: "Spelling and Grammar")
        let spellingItem = NSMenuItem(title: spellingTitle, action: nil, keyEquivalent: "")
        let spellingMenu = NSMenu(title: spellingTitle)

        let showItem = NSMenuItem(
            title: L10n.string("app.menu.spelling.show", defaultValue: "Show Spelling and Grammar"),
            action: #selector(NSText.showGuessPanel(_:)),
            keyEquivalent: ":"
        )
        showItem.keyEquivalentModifierMask = [.command]
        spellingMenu.addItem(showItem)

        let checkItem = NSMenuItem(
            title: L10n.string("app.menu.spelling.checkNow", defaultValue: "Check Document Now"),
            action: #selector(NSText.checkSpelling(_:)),
            keyEquivalent: ";"
        )
        checkItem.keyEquivalentModifierMask = [.command]
        spellingMenu.addItem(checkItem)

        spellingMenu.addItem(.separator())
        spellingMenu.addItem(NSMenuItem(title: L10n.string("app.menu.spelling.checkWhileTyping", defaultValue: "Check Spelling While Typing"), action: #selector(NSTextView.toggleContinuousSpellChecking(_:)), keyEquivalent: ""))
        spellingMenu.addItem(NSMenuItem(title: L10n.string("app.menu.spelling.checkGrammar", defaultValue: "Check Grammar With Spelling"), action: #selector(NSTextView.toggleGrammarChecking(_:)), keyEquivalent: ""))
        spellingMenu.addItem(NSMenuItem(title: L10n.string("app.menu.spelling.correctAutomatically", defaultValue: "Correct Spelling Automatically"), action: #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)), keyEquivalent: ""))

        spellingItem.submenu = spellingMenu
        editMenu.addItem(.separator())
        editMenu.addItem(spellingItem)
    }

    // MARK: - Export / Print menu injection

    private func injectExportPrintIfNeeded() {
        guard let fileMenu = fileMenu() else { return }
        guard !fileMenu.items.contains(where: { $0.action == #selector(exportPDFAction(_:)) }) else { return }

        let exportItem = NSMenuItem(
            title: L10n.string("app.menu.exportPdf", defaultValue: "Export as PDF…"),
            action: #selector(exportPDFAction(_:)),
            keyEquivalent: "e"
        )
        exportItem.keyEquivalentModifierMask = [.command, .shift]
        exportItem.target = self

        let printItem = NSMenuItem(
            title: L10n.string("app.menu.print", defaultValue: "Print…"),
            action: #selector(printDocumentAction(_:)),
            keyEquivalent: "p"
        )
        printItem.keyEquivalentModifierMask = [.command, .shift]
        printItem.target = self

        fileMenu.addItem(.separator())
        fileMenu.addItem(exportItem)
        fileMenu.addItem(printItem)
    }

    @objc private func exportPDFAction(_ sender: Any?) {
        let workspace = WorkspaceManager.shared
        guard workspace.activeDocumentID != nil else { return }
        let fontSize = UserDefaults.standard.double(forKey: "editorFontSize")
        PDFExporter().exportPDF(
            markdown: workspace.currentFileText,
            fontSize: CGFloat(fontSize > 0 ? fontSize : 16),
            fileURL: workspace.currentFileURL
        )
    }

    @objc private func printDocumentAction(_ sender: Any?) {
        let workspace = WorkspaceManager.shared
        guard workspace.activeDocumentID != nil else { return }
        let fontSize = UserDefaults.standard.double(forKey: "editorFontSize")
        PDFExporter().printHTML(
            markdown: workspace.currentFileText,
            fontSize: CGFloat(fontSize > 0 ? fontSize : 16),
            fileURL: workspace.currentFileURL
        )
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(exportPDFAction(_:)) ||
           menuItem.action == #selector(printDocumentAction(_:)) {
            return WorkspaceManager.shared.activeDocumentID != nil
        }
        return true
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        if hasDocumentWindows() && NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        if isForegroundActivation, !hasDocumentWindows(), mainWindow == nil {
            createMainWindow()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard isForegroundActivation, !hasDocumentWindows(), mainWindow == nil else { return }
        createMainWindow()
    }

    func applicationDidUnhide(_ notification: Notification) {
        guard isForegroundActivation, !hasDocumentWindows(), mainWindow == nil else { return }
        createMainWindow()
    }

    func ensureMainWindowIfNeeded() {
        guard isForegroundActivation, !hasDocumentWindows(), mainWindow == nil else { return }
        createMainWindow()
    }

    func handleMainWindowWillClose() {
        mainWindow = nil
        splitViewController = nil
        if let themeObserver {
            NotificationCenter.default.removeObserver(themeObserver)
            self.themeObserver = nil
        }
        hideLauncherWindow()
        DispatchQueue.main.async { [weak self] in
            self?.updateActivationPolicy()
        }
    }

    private func refreshLocalizedUI() {
        splitViewController?.refreshLocalizedViews()
        refreshLocalizedMenuTitles()
        refreshSwiftUICommandMenuTitles()
        NSApp.mainMenu?.update()
    }

    private func refreshSwiftUICommandMenuTitles() {
        let menu = NSApp.mainMenu
        let topLevelReplacements: [(key: String, defaultValue: String)] = [
            ("app.menu.file", "File"),
            ("app.menu.edit", "Edit"),
            ("app.menu.view", "View"),
            ("app.menu.window", "Window"),
            ("app.menu.help", "Help"),
            ("app.menu.format", "Format")
        ]
        let replacements: [(key: String, defaultValue: String)] = [
            ("app.menu.newDocument", "New Document"),
            ("app.menu.open", "Open…"),
            ("app.menu.save", "Save"),
            ("app.menu.hideHiddenFiles", "Hide Hidden Files"),
            ("app.menu.showHiddenFiles", "Show Hidden Files"),
            ("app.menu.help.clearlyHelp", "Clearly Help"),
            ("app.menu.help.sampleDocument", "Sample Document"),
            ("app.menu.help.exportDiagnosticLog", "Export Diagnostic Log…"),
            ("app.menu.format", "Format"),
            ("app.menu.format.bold", "Bold"),
            ("app.menu.format.italic", "Italic"),
            ("app.menu.format.strikethrough", "Strikethrough"),
            ("app.menu.format.heading", "Heading"),
            ("app.menu.format.link", "Link…"),
            ("app.menu.format.image", "Image…"),
            ("app.menu.format.bulletList", "Bullet List"),
            ("app.menu.format.numberedList", "Numbered List"),
            ("app.menu.format.todo", "Todo"),
            ("app.menu.format.quote", "Quote"),
            ("app.menu.format.horizontalRule", "Horizontal Rule"),
            ("app.menu.format.table", "Table"),
            ("app.menu.format.code", "Code"),
            ("app.menu.format.codeBlock", "Code Block"),
            ("app.menu.format.math", "Math"),
            ("app.menu.format.mathBlock", "Math Block"),
            ("app.menu.format.pageBreak", "Page Break"),
            ("app.menu.find", "Find…"),
            ("app.menu.font.increase", "Increase Font Size"),
            ("app.menu.font.decrease", "Decrease Font Size"),
            ("app.menu.checkForUpdates", "Check for Updates…"),
            ("app.menu.exportPdf", "Export as PDF…"),
            ("app.menu.print", "Print…")
        ]

        for replacement in topLevelReplacements {
            updateTopLevelMenuTitle(
                key: replacement.key,
                defaultValue: replacement.defaultValue,
                title: L10n.string(replacement.key, defaultValue: replacement.defaultValue)
            )
        }

        for replacement in replacements {
            updateMenuTitles(
                in: menu,
                key: replacement.key,
                defaultValue: replacement.defaultValue,
                title: L10n.string(replacement.key, defaultValue: replacement.defaultValue)
            )
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

        Task { @MainActor in
            ScratchpadManager.shared.closeAll()
            QuickSwitcherManager.shared.dismiss()
        }
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
            hideLauncherWindow()
            if NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
            if NSApp.isActive {
                NSApp.hide(nil)
            }
        }
    }

    /// A "document window" is any user-facing window that isn't a scratchpad,
    /// MenuBarExtra panel, sheet, or internal SwiftUI bookkeeping window.
    private func hasDocumentWindows() -> Bool {
        NSApp.windows.contains { WindowRouter.isVisibleUserFacingDocumentWindow($0) }
    }

    private var isForegroundActivation: Bool {
        guard NSApp.isActive else { return false }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    private func hideLauncherWindow() {
        for window in NSApp.windows where window.identifier == WindowRouter.launcherWindowIdentifier {
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window.orderOut(nil)
        }
    }

    private func persistSidebarVisibility(_ visible: Bool) {
        let workspace = WorkspaceManager.shared
        workspace.isSidebarVisible = visible
        UserDefaults.standard.set(visible, forKey: "sidebarVisible")
    }

    func setSidebarVisible(_ visible: Bool, animated: Bool = true) {
        splitViewController?.setSidebarVisible(visible, animated: animated)
        persistSidebarVisibility(visible)
    }

    func doToggleSidebar() {
        if let sidebarItem = splitViewController?.splitViewItems.first {
            setSidebarVisible(sidebarItem.isCollapsed)
        } else {
            setSidebarVisible(!WorkspaceManager.shared.isSidebarVisible, animated: false)
        }
    }

    func shouldCloseToMenuBar(for event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        guard event.charactersIgnoringModifiers?.lowercased() == "q" else { return false }
        guard !AppLanguagePreference.hasPendingChange else { return false }

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



// MARK: - Custom split view with soft divider

private class SoftDividerSplitView: NSSplitView {
    override var dividerColor: NSColor {
        return .separatorColor
    }
}

// MARK: - NSSplitViewController (AppKit sidebar, like Things/Bear/Mail)

@MainActor
class ClearlySplitViewController: NSSplitViewController {
    let workspace: WorkspaceManager
    private var needsInitialCollapse = false
    private weak var sidebarViewController: SidebarViewController?
    private weak var detailHostController: NSHostingController<AnyView>?

    init(workspace: WorkspaceManager) {
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        // Set custom split view before super creates one
        let customSplit = SoftDividerSplitView()
        customSplit.isVertical = true
        customSplit.dividerStyle = .thin
        self.splitView = customSplit
        super.loadView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Sidebar — pure AppKit, no NSHostingView (avoids opaque white background)
        let sidebarVC = SidebarViewController(workspace: workspace)
        self.sidebarViewController = sidebarVC
        let sidebarItem = NSSplitViewItem(contentListWithViewController: sidebarVC)
        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 300
        addSplitViewItem(sidebarItem)

        // Detail
        let detailHost = NSHostingController(rootView: localizedDetailView())
        self.detailHostController = detailHost
        let detailItem = NSSplitViewItem(viewController: detailHost)
        detailItem.minimumThickness = 400
        addSplitViewItem(detailItem)

        if !workspace.isSidebarVisible {
            needsInitialCollapse = true
        }
    }

    private func localizedDetailView() -> AnyView {
        AnyView(
            DetailView(workspace: workspace)
                .environment(\.locale, Locale(identifier: AppLanguage.currentLocalization()))
        )
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if needsInitialCollapse {
            needsInitialCollapse = false
            splitViewItems.first?.isCollapsed = true
        }
    }

    func setSidebarVisible(_ visible: Bool, animated: Bool) {
        guard let sidebarItem = splitViewItems.first else { return }
        let targetCollapsed = !visible
        guard sidebarItem.isCollapsed != targetCollapsed else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                sidebarItem.animator().isCollapsed = targetCollapsed
            }
        } else {
            sidebarItem.isCollapsed = targetCollapsed
        }
    }

    func refreshLocalizedViews() {
        detailHostController?.rootView = localizedDetailView()
        sidebarViewController?.refreshLocalizedViews()
    }

    override func toggleSidebar(_ sender: Any?) {
        guard let appDelegate = NSApp.delegate as? ClearlyAppDelegate,
              let sidebarItem = splitViewItems.first else { return }
        appDelegate.setSidebarVisible(sidebarItem.isCollapsed)
    }
}

// MARK: - Detail view (editor/preview + header bar)

struct DetailView: View {
    @Bindable var workspace: WorkspaceManager

    var body: some View {
        if workspace.activeDocumentID != nil {
            ContentView(workspace: workspace)
        } else {
            NoFileView(workspace: workspace)
        }
    }
}



// MARK: - Empty State (no file open)

struct NoFileView: View {
    var workspace: WorkspaceManager

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Image(systemName: "doc.text")
                    .font(.system(size: 40))
                    .foregroundStyle(.quaternary)
                    .padding(.bottom, 12)
                Text(L10n.string("app.empty.noFileOpen", defaultValue: "No File Open"))
                    .font(.system(size: 20, weight: .medium, design: .default))
                    .foregroundStyle(.secondary)
                    .tracking(-0.2)
                    .padding(.bottom, 6)
                Text(L10n.string("app.empty.noFileSubtitle", defaultValue: "Create a new document or open an existing file"))
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 20)
                HStack(spacing: 12) {
                    Button(L10n.string("app.menu.newDocument", defaultValue: "New Document")) {
                        workspace.createUntitledDocument()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    Button(L10n.string("app.menu.open", defaultValue: "Open…")) {
                        workspace.showOpenPanel()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .position(x: geo.size.width / 2, y: geo.size.height * 0.4)
        }
        .background(Theme.backgroundColorSwiftUI)
    }
}

@main
struct ClearlyApp: App {
    @NSApplicationDelegateAdaptor(ClearlyAppDelegate.self) var appDelegate
    @AppStorage(AppLanguagePreference.userDefaultsKey) private var appLanguagePreference = AppLanguagePreference.system.rawValue
    @AppStorage("themePreference") private var themePreference = "system"
    @State private var scratchpadManager = ScratchpadManager.shared
    private let workspace = WorkspaceManager.shared
    #if canImport(Sparkle)
    private let updaterController: SPUStandardUpdaterController
    #endif

    init() {
        AppLanguagePreference.configureDefaultPreference()
        let appliedPreference = UserDefaults.standard.string(forKey: AppLanguagePreference.userDefaultsKey)
            ?? AppLanguagePreference.system.rawValue
        UserDefaults.standard.set(appliedPreference, forKey: AppLanguagePreference.appliedUserDefaultsKey)
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

    private var resolvedLanguageIdentifier: String {
        (AppLanguagePreference(rawValue: appLanguagePreference) ?? .system).localeIdentifier
    }

    private var appLocale: Locale {
        Locale(identifier: resolvedLanguageIdentifier)
    }

    var body: some Scene {
        Window("Clearly", id: "launcher") {
            LauncherSceneMarker()
                .frame(width: 0, height: 0)
                .hidden()
                .environment(\.locale, appLocale)
        }
        .defaultSize(width: 1, height: 1)
        .commands {
            // Replace New/Open with our own
            CommandGroup(replacing: .newItem) {
                Button(L10n.string("app.menu.newDocument", defaultValue: "New Document")) {
                    workspace.createUntitledDocument()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button(L10n.string("app.menu.open", defaultValue: "Open…")) {
                    workspace.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            // Save
            CommandGroup(replacing: .saveItem) {
                Button(L10n.string("app.menu.save", defaultValue: "Save")) {
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
            CommandGroup(replacing: .printItem) { }
            // View menu — sidebar, editor/preview modes, outline
            CommandGroup(before: .toolbar) {
                // Toggle Sidebar, Editor/Preview, and Toggle Outline
                // are handled via AppKit menu injection in AppDelegate

                Button {
                    workspace.toggleShowHiddenFiles()
                } label: {
                    Text(
                        workspace.showHiddenFiles
                        ? L10n.string("app.menu.hideHiddenFiles", defaultValue: "Hide Hidden Files")
                        : L10n.string("app.menu.showHiddenFiles", defaultValue: "Show Hidden Files")
                    )
                }
            }

            CommandGroup(after: .textEditing) {
                FindCommand()
            }
            CommandGroup(replacing: .help) {
                Button(L10n.string("app.menu.help.clearlyHelp", defaultValue: "Clearly Help")) {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Shpigford/clearly/issues")!)
                }
                Divider()
                Button(L10n.string("app.menu.help.sampleDocument", defaultValue: "Sample Document")) {
                    if let url = Bundle.main.url(forResource: "demo", withExtension: "md"),
                       let content = try? String(contentsOf: url, encoding: .utf8) {
                        workspace.createDocumentWithContent(content)
                    }
                }
                Divider()
                Button(L10n.string("app.menu.help.exportDiagnosticLog", defaultValue: "Export Diagnostic Log…")) {
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
            CommandGroup(replacing: .textFormatting) {
                FontSizeCommands()
                Divider()
                Button(L10n.string("app.menu.format.bold", defaultValue: "Bold")) {
                    NSApp.sendAction(#selector(ClearlyTextView.toggleBold(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("b", modifiers: .command)

                Button(L10n.string("app.menu.format.italic", defaultValue: "Italic")) {
                    NSApp.sendAction(#selector(ClearlyTextView.toggleItalic(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("i", modifiers: .command)

                Button(L10n.string("app.menu.format.strikethrough", defaultValue: "Strikethrough")) {
                    NSApp.sendAction(#selector(ClearlyTextView.toggleStrikethrough(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])

                Button(L10n.string("app.menu.format.heading", defaultValue: "Heading")) {
                    NSApp.sendAction(#selector(ClearlyTextView.insertHeading(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Divider()

                Button(L10n.string("app.menu.format.link", defaultValue: "Link…")) {
                    NSApp.sendAction(#selector(ClearlyTextView.insertLink(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button(L10n.string("app.menu.format.image", defaultValue: "Image…")) {
                    NSApp.sendAction(#selector(ClearlyTextView.insertImage(_:)), to: nil, from: nil)
                }

                Divider()

                Button(L10n.string("app.menu.format.bulletList", defaultValue: "Bullet List")) {
                    NSApp.sendAction(#selector(ClearlyTextView.toggleBulletList(_:)), to: nil, from: nil)
                }

                Button(L10n.string("app.menu.format.numberedList", defaultValue: "Numbered List")) {
                    NSApp.sendAction(#selector(ClearlyTextView.toggleNumberedList(_:)), to: nil, from: nil)
                }

                Button(L10n.string("app.menu.format.todo", defaultValue: "Todo")) {
                    NSApp.sendAction(#selector(ClearlyTextView.toggleTodoList(_:)), to: nil, from: nil)
                }

                Divider()

                Button(L10n.string("app.menu.format.quote", defaultValue: "Quote")) {
                    NSApp.sendAction(#selector(ClearlyTextView.toggleBlockquote(_:)), to: nil, from: nil)
                }

                Button(L10n.string("app.menu.format.horizontalRule", defaultValue: "Horizontal Rule")) {
                    NSApp.sendAction(#selector(ClearlyTextView.insertHorizontalRule(_:)), to: nil, from: nil)
                }

                Button(L10n.string("app.menu.format.table", defaultValue: "Table")) {
                    NSApp.sendAction(#selector(ClearlyTextView.insertMarkdownTable(_:)), to: nil, from: nil)
                }

                Divider()

                Button(L10n.string("app.menu.format.code", defaultValue: "Code")) {
                    NSApp.sendAction(#selector(ClearlyTextView.toggleInlineCode(_:)), to: nil, from: nil)
                }

                Button(L10n.string("app.menu.format.codeBlock", defaultValue: "Code Block")) {
                    NSApp.sendAction(#selector(ClearlyTextView.insertCodeBlock(_:)), to: nil, from: nil)
                }

                Divider()

                Button(L10n.string("app.menu.format.math", defaultValue: "Math")) {
                    NSApp.sendAction(#selector(ClearlyTextView.toggleInlineMath(_:)), to: nil, from: nil)
                }

                Button(L10n.string("app.menu.format.mathBlock", defaultValue: "Math Block")) {
                    NSApp.sendAction(#selector(ClearlyTextView.insertMathBlock(_:)), to: nil, from: nil)
                }

                Divider()

                Button(L10n.string("app.menu.format.pageBreak", defaultValue: "Page Break")) {
                    NSApp.sendAction(#selector(ClearlyTextView.insertPageBreak(_:)), to: nil, from: nil)
                }
            }
        }

        Settings {
            #if canImport(Sparkle)
            SettingsView(updater: updaterController.updater)
                .environment(\.locale, appLocale)
                .preferredColorScheme(resolvedColorScheme)
            #else
            SettingsView()
                .environment(\.locale, appLocale)
                .preferredColorScheme(resolvedColorScheme)
            #endif
        }

        MenuBarExtra(L10n.string("app.menubar.scratchpads", defaultValue: "Scratchpads"), image: "ScratchpadMenuBarIcon") {
            ScratchpadMenuBar(manager: scratchpadManager)
                .environment(\.locale, appLocale)
        }
    }

}

struct FindCommand: View {
    @FocusedValue(\.findState) var findState

    var body: some View {
        Button(L10n.string("app.menu.find", defaultValue: "Find…")) {
            findState?.present()
        }
        .keyboardShortcut("f", modifiers: .command)
    }
}

struct OutlineToggleCommand: View {
    @FocusedValue(\.outlineState) var outlineState

    var body: some View {
        Button(L10n.string("app.menu.toggleOutline", defaultValue: "Toggle Outline")) {
            outlineState?.toggle()
        }
        .keyboardShortcut("o", modifiers: [.command, .shift])
    }
}

struct ViewModeCommands: View {
    @FocusedValue(\.viewMode) var mode

    var body: some View {
        Button(L10n.string("app.menu.view.editor", defaultValue: "Editor")) {
            mode?.wrappedValue = .edit
        }
        .keyboardShortcut("1", modifiers: .command)

        Button(L10n.string("app.menu.view.preview", defaultValue: "Preview")) {
            mode?.wrappedValue = .preview
        }
        .keyboardShortcut("2", modifiers: .command)
    }
}

// MARK: - Font Size Commands

struct FontSizeCommands: View {
    @AppStorage("editorFontSize") private var fontSize: Double = 16

    var body: some View {
        Button(L10n.string("app.menu.font.increase", defaultValue: "Increase Font Size")) {
            fontSize = min(fontSize + 1, 24)
        }
        .keyboardShortcut("+", modifiers: .command)

        Button(L10n.string("app.menu.font.decrease", defaultValue: "Decrease Font Size")) {
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
        Button(L10n.string("app.menu.checkForUpdates", defaultValue: "Check for Updates…")) {
            updater.checkForUpdates()
        }
        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}
#endif

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
