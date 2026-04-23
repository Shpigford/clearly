import SwiftUI
import ClearlyCore
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

    func showMainWindow() {
        activateDocumentApp()
        if let window = NSApp.windows.first(where: { Self.isUserFacingDocumentWindow($0) }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
        // With the SwiftUI `Window("Clearly", id: "main")` scene, the window is
        // re-presented automatically when the app activates — no imperative
        // fallback needed.
    }

    static func isUserFacingDocumentWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel), !window.isSheet, window.level != .floating else { return false }
        return window.frame.width >= 200 && window.frame.height >= 200
    }

    static func isVisibleUserFacingDocumentWindow(_ window: NSWindow) -> Bool {
        isUserFacingDocumentWindow(window) && (window.isVisible || window.isMiniaturized)
    }
}

// MARK: - App Delegate (dock icon management + file open handling)

@MainActor
final class ClearlyAppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    static private(set) weak var shared: ClearlyAppDelegate?

    private var observers: [Any] = []
    private var commandQMonitor: Any?
    private var closeTabMonitor: Any?
    private var showHiddenFilesMonitor: Any?
    private var sidebarToggleMonitor: Any?
    private var middleClickMonitor: Any?
    private var quickSwitcherMonitor: Any?
    private var themeObserver: Any?
    private var isProgrammaticallyClosingWindows = false

    /// Returns the active main document window if SwiftUI has presented one.
    var mainWindow: NSWindow? {
        NSApp.windows.first { WindowRouter.isUserFacingDocumentWindow($0) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        // A normal Launch Services open activates the app and opens a document window.
        // Login-item launch stays inactive with no document windows, so collapse to
        // menubar-only only in that state instead of guessing from parent PID.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            if !NSApp.isActive && !self.hasDocumentWindows() {
                NSApp.setActivationPolicy(.accessory)
            }
        }

        // SwiftUI's `Window("Clearly", id: "main")` scene creates the window at
        // launch. No imperative creation path is needed.

        // Listen for tag filter requests (from sidebar tag clicks and preview tag links)
        NotificationCenter.default.addObserver(
            forName: .init("ClearlyFilterByTag"), object: nil, queue: .main
        ) { notification in
            guard let tag = notification.userInfo?["tag"] as? String else { return }
            QuickSwitcherManager.shared.show(tagFilter: tag)
        }

        // Watch multiple signals — window close, app deactivate, main window change
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
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

        commandQMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.shouldCloseToMenuBar(for: event) else { return event }
            self.closeDocumentWindowsToMenuBar()
            return nil
        }

        closeTabMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            guard chars == "w" && mods == [.command] else { return event }
            guard let window = event.window,
                  WindowRouter.isUserFacingDocumentWindow(window) else { return event }
            let workspace = WorkspaceManager.shared
            if let activeID = workspace.activeDocumentID {
                workspace.closeDocument(activeID)
                return nil
            }
            return event
        }

        middleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { event in
            guard event.buttonNumber == 2 else { return event }
            let workspace = WorkspaceManager.shared
            if let hoveredID = workspace.hoveredTabID {
                workspace.closeDocument(hoveredID)
                return nil
            }
            return event
        }

        showHiddenFilesMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.shouldToggleHiddenFiles(for: event) else { return event }
            WorkspaceManager.shared.toggleShowHiddenFiles()
            return nil
        }

        // Cmd+L toggles sidebar, Cmd+Shift+L jumps to line, Cmd+1/2 switches mode
        sidebarToggleMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard event.type == .keyDown else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

            if chars == "l" && mods == [.command] {
                self.doToggleSidebar()
                return nil
            }
            if chars == "l" && mods == [.command, .shift] {
                NotificationCenter.default.post(name: .init("ClearlyJumpToLine"), object: nil)
                return nil
            }
            if chars == "1" && mods == [.command] {
                WorkspaceManager.shared.currentViewMode = .edit
                return nil
            }
            if chars == "2" && mods == [.command] {
                WorkspaceManager.shared.currentViewMode = .preview
                return nil
            }
            if chars == "t" && mods == [.command] {
                WorkspaceManager.shared.createUntitledDocument()
                return nil
            }
            if chars == "[" && mods == [.command, .shift] {
                WorkspaceManager.shared.selectPreviousTab()
                return nil
            }
            if chars == "]" && mods == [.command, .shift] {
                WorkspaceManager.shared.selectNextTab()
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
                    let shouldShowGettingStarted = workspace.isFirstRun
                    if workspace.addLocation(url: url), shouldShowGettingStarted {
                        workspace.handleFirstLocationIfNeeded(folderURL: url)
                    }
                }
            } else {
                openedFile = workspace.openFileInNewTab(at: url) || openedFile
            }
        }
        if openedDirectory {
            persistSidebarVisibility(true)
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
        if let closeTabMonitor {
            NSEvent.removeMonitor(closeTabMonitor)
            self.closeTabMonitor = nil
        }
        if let middleClickMonitor {
            NSEvent.removeMonitor(middleClickMonitor)
            self.middleClickMonitor = nil
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
        injectGlobalSearchIfNeeded()
        injectExportPrintIfNeeded()
    }

    private func injectGlobalSearchIfNeeded() {
        guard let viewMenu = NSApp.mainMenu?.item(withTitle: "View")?.submenu else { return }
        guard !viewMenu.items.contains(where: { $0.title == "Search All Files…" }) else { return }

        let item = NSMenuItem(title: "Search All Files…", action: #selector(globalSearchAction(_:)), keyEquivalent: "f")
        item.keyEquivalentModifierMask = [.command, .shift]
        item.target = self

        if let quickOpenIndex = viewMenu.items.firstIndex(where: { $0.title == "Quick Open…" }) {
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
        guard let viewMenu = NSApp.mainMenu?.item(withTitle: "View")?.submenu else { return }
        guard !viewMenu.items.contains(where: { $0.title == "Toggle Sidebar" }) else { return }

        let sidebarItem = NSMenuItem(title: "Toggle Sidebar", action: #selector(toggleSidebarMenuAction(_:)), keyEquivalent: "l")
        sidebarItem.keyEquivalentModifierMask = [.command]
        sidebarItem.target = self

        // Insert at the beginning of the View menu
        viewMenu.insertItem(sidebarItem, at: 0)
        viewMenu.insertItem(.separator(), at: 1)
    }

    @objc private func toggleSidebarMenuAction(_ sender: Any?) {
        doToggleSidebar()
    }

    private func injectQuickOpenIfNeeded() {
        guard let viewMenu = NSApp.mainMenu?.item(withTitle: "View")?.submenu else { return }
        guard !viewMenu.items.contains(where: { $0.title == "Quick Open…" }) else { return }

        let item = NSMenuItem(title: "Quick Open…", action: #selector(quickOpenAction(_:)), keyEquivalent: "p")
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
        guard let viewMenu = NSApp.mainMenu?.item(withTitle: "View")?.submenu else { return }

        // Remove tab bar items (system-injected, we don't use tabs)
        viewMenu.items.removeAll { $0.title == "Show Tab Bar" || $0.title == "Show All Tabs" || $0.title == "Hide Tab Bar" }

        guard !viewMenu.items.contains(where: { $0.title == "Toggle Outline" }) else { return }

        let outlineItem = NSMenuItem(title: "Toggle Outline", action: #selector(toggleOutlineAction(_:)), keyEquivalent: "o")
        outlineItem.keyEquivalentModifierMask = [.command, .shift]
        outlineItem.target = self

        let backlinksItem = NSMenuItem(title: "Toggle Backlinks", action: #selector(toggleBacklinksAction(_:)), keyEquivalent: "b")
        backlinksItem.keyEquivalentModifierMask = [.command, .shift]
        backlinksItem.target = self

        let lineNumbersItem = NSMenuItem(title: "Line Numbers", action: #selector(toggleLineNumbersAction(_:)), keyEquivalent: "")
        lineNumbersItem.target = self

        let editorItem = NSMenuItem(title: "Editor", action: #selector(switchToEditorAction(_:)), keyEquivalent: "1")
        editorItem.keyEquivalentModifierMask = [.command]
        editorItem.target = self

        let previewItem = NSMenuItem(title: "Preview", action: #selector(switchToPreviewAction(_:)), keyEquivalent: "2")
        previewItem.keyEquivalentModifierMask = [.command]
        previewItem.target = self

        // Insert right after Toggle Sidebar (index 0)
        var insertIndex = 1
        viewMenu.insertItem(outlineItem, at: insertIndex); insertIndex += 1
        viewMenu.insertItem(backlinksItem, at: insertIndex); insertIndex += 1
        viewMenu.insertItem(lineNumbersItem, at: insertIndex); insertIndex += 1
        viewMenu.insertItem(.separator(), at: insertIndex); insertIndex += 1
        viewMenu.insertItem(editorItem, at: insertIndex); insertIndex += 1
        viewMenu.insertItem(previewItem, at: insertIndex); insertIndex += 1

        // Preview Font submenu
        viewMenu.insertItem(.separator(), at: insertIndex); insertIndex += 1
        let fontSubmenu = NSMenu(title: "Preview Font")
        for (title, value) in [("San Francisco", "sanFrancisco"), ("New York", "newYork"), ("SF Mono", "sfMono")] {
            let item = NSMenuItem(title: title, action: #selector(setPreviewFontAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            fontSubmenu.addItem(item)
        }
        let fontMenuItem = NSMenuItem(title: "Preview Font", action: nil, keyEquivalent: "")
        fontMenuItem.submenu = fontSubmenu
        viewMenu.insertItem(fontMenuItem, at: insertIndex)
    }

    @objc private func switchToEditorAction(_ sender: Any?) {
        WorkspaceManager.shared.currentViewMode = .edit
    }

    @objc private func switchToPreviewAction(_ sender: Any?) {
        WorkspaceManager.shared.currentViewMode = .preview
    }

    @objc private func toggleOutlineAction(_ sender: Any?) {
        NotificationCenter.default.post(name: .init("ClearlyToggleOutline"), object: nil)
    }

    @objc private func toggleBacklinksAction(_ sender: Any?) {
        NotificationCenter.default.post(name: .init("ClearlyToggleBacklinks"), object: nil)
    }

    @objc private func toggleLineNumbersAction(_ sender: Any?) {
        NotificationCenter.default.post(name: .init("ClearlyToggleLineNumbers"), object: nil)
    }

    @objc private func setPreviewFontAction(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        UserDefaults.standard.set(value, forKey: "previewFontFamily")
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

    // MARK: - Export / Print menu injection

    private func injectExportPrintIfNeeded() {
        guard let fileMenu = NSApp.mainMenu?.item(withTitle: "File")?.submenu else { return }
        guard !fileMenu.items.contains(where: { $0.title == "Export as PDF…" }) else { return }

        let exportItem = NSMenuItem(title: "Export as PDF…", action: #selector(exportPDFAction(_:)), keyEquivalent: "e")
        exportItem.keyEquivalentModifierMask = [.command, .shift]
        exportItem.target = self

        let printItem = NSMenuItem(title: "Print…", action: #selector(printDocumentAction(_:)), keyEquivalent: "p")
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
        let fontFamily = UserDefaults.standard.string(forKey: "previewFontFamily") ?? "sanFrancisco"
        PDFExporter().exportPDF(
            markdown: workspace.currentFileText,
            fontSize: CGFloat(fontSize > 0 ? fontSize : Theme.editorFontSize),
            fontFamily: fontFamily,
            fileURL: workspace.currentFileURL
        )
    }

    @objc private func printDocumentAction(_ sender: Any?) {
        let workspace = WorkspaceManager.shared
        guard workspace.activeDocumentID != nil else { return }
        let fontSize = UserDefaults.standard.double(forKey: "editorFontSize")
        let fontFamily = UserDefaults.standard.string(forKey: "previewFontFamily") ?? "sanFrancisco"
        PDFExporter().printHTML(
            markdown: workspace.currentFileText,
            fontSize: CGFloat(fontSize > 0 ? fontSize : Theme.editorFontSize),
            fontFamily: fontFamily,
            fileURL: workspace.currentFileURL
        )
    }

    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(exportPDFAction(_:)) ||
           menuItem.action == #selector(printDocumentAction(_:)) {
            return WorkspaceManager.shared.activeDocumentID != nil
        }
        if menuItem.action == #selector(toggleLineNumbersAction(_:)) {
            menuItem.state = UserDefaults.standard.bool(forKey: "showLineNumbers") ? .on : .off
            return true
        }
        if menuItem.action == #selector(setPreviewFontAction(_:)) {
            let current = UserDefaults.standard.string(forKey: "previewFontFamily") ?? "sanFrancisco"
            menuItem.state = (menuItem.representedObject as? String) == current ? .on : .off
            return true
        }
        return true
    }

    func applicationWillBecomeActive(_ notification: Notification) {
        if hasDocumentWindows() && NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        bringMainWindowToFrontIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        bringMainWindowToFrontIfNeeded()
    }

    func applicationDidUnhide(_ notification: Notification) {
        bringMainWindowToFrontIfNeeded()
    }

    /// SwiftUI handles window creation via the `Window("Clearly", id: "main")`
    /// scene — we just need to bring whichever instance exists to the front on
    /// dock clicks and re-activation events.
    private func bringMainWindowToFrontIfNeeded() {
        guard isForegroundActivation, !ScratchpadManager.shared.hasOpenWindows else { return }
        if let window = NSApp.windows.first(where: { WindowRouter.isUserFacingDocumentWindow($0) }) {
            window.makeKeyAndOrderFront(nil)
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

    private func updateActivationPolicy() {
        if hasDocumentWindows() {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
        } else {
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

    private func persistSidebarVisibility(_ visible: Bool) {
        let workspace = WorkspaceManager.shared
        workspace.isSidebarVisible = visible
        UserDefaults.standard.set(visible, forKey: "sidebarVisible")
    }

    /// ⌘L toggles the NavigationSplitView sidebar by firing the AppKit
    /// responder-chain action on the active split view controller. SwiftUI's
    /// `NavigationSplitView` wraps an `NSSplitViewController` under the hood,
    /// so `toggleSidebar(_:)` works as long as it's routed through the active
    /// window's first responder chain.
    func doToggleSidebar() {
        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
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
        guard WindowRouter.isUserFacingDocumentWindow(window) else { return false }

        return true
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
        #if DEBUG
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        #else
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
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
        Window("Clearly", id: "main") {
            MacRootView(workspace: workspace)
                .preferredColorScheme(resolvedColorScheme)
        }
        .defaultSize(width: 1100, height: 720)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            // Replace New/Open with our own
            CommandGroup(replacing: .newItem) {
                Button("New Document") {
                    workspace.createUntitledDocument()
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Tab") {
                    workspace.createUntitledDocument()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Open…") {
                    workspace.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    ForEach(workspace.recentFiles, id: \.self) { url in
                        Button(url.deletingPathExtension().lastPathComponent) {
                            workspace.openFile(at: url)
                        }
                    }
                    Divider()
                    Button("Clear Menu") {
                        workspace.clearRecents()
                    }
                }
                .disabled(workspace.recentFiles.isEmpty)
            }

            // Save
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    workspace.saveCurrentFile()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(workspace.activeDocumentID == nil)

                Divider()

                Button(workspace.currentFileURL.map { workspace.isPinned($0) ? "Unpin Document" : "Pin Document" } ?? "Pin Document") {
                    if let url = workspace.currentFileURL {
                        workspace.togglePin(url)
                    }
                }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(workspace.currentFileURL == nil)
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

                Button(workspace.showHiddenFiles ? "Hide Hidden Files" : "Show Hidden Files") {
                    workspace.toggleShowHiddenFiles()
                }
            }

            CommandGroup(after: .textEditing) {
                FindCommand()
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
                Button("What’s New…") {
                    NSWorkspace.shared.open(URL(string: "https://clearly.md/changelog")!)
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
            CommandGroup(replacing: .textFormatting) {
                FontSizeCommands()
                Divider()
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
            findState?.toggle()
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
