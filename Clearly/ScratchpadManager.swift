import AppKit
import SwiftUI
import UniformTypeIdentifiers
import KeyboardShortcuts
import ClearlyCore

private final class ScratchpadPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
@Observable
final class ScratchpadManager {
    static let shared = ScratchpadManager()

    private(set) var currentNoteID: ScratchpadNote.ID?
    var deleteUndo = ScratchpadDeleteUndoController()
    var historyPopoverShown: Bool = false

    private let store = ScratchpadStore.shared
    private var window: ScratchpadPanel?
    private var windowDelegate: WindowDelegate?

    var isWindowVisible: Bool { window?.isVisible == true }

    private init() {
        KeyboardShortcuts.onKeyUp(for: .newScratchpad) { [weak self] in
            Task { @MainActor in self?.showOrFocus() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                ScratchpadStore.shared.refresh()
                self.runRetentionSweep()
            }
        }
    }

    // MARK: - Window lifecycle

    func showOrFocus() {
        ensureWindow()
        if currentNoteID == nil || store.notes.first(where: { $0.id == currentNoteID }) == nil {
            currentNoteID = store.ensureNonEmpty().id
        }
        if let id = currentNoteID, let note = store.notes.first(where: { $0.id == id }) {
            store.touchOpened(note)
        }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func createAndShowNew() {
        ensureWindow()
        store.flushPendingWrites()
        let note = store.create()
        select(note: note)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func select(note: ScratchpadNote) {
        store.flushPendingWrites()
        currentNoteID = note.id
        store.touchOpened(note)
    }

    var currentNote: ScratchpadNote? {
        guard let id = currentNoteID else { return nil }
        return store.notes.first(where: { $0.id == id })
    }

    // MARK: - Save as Document

    func saveCurrentAsDocument() {
        guard let window, let note = currentNote else { return }
        store.flushPendingWrites()
        let text = store.loadText(for: note)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.daringFireballMarkdown]
        let suggestion = note.title == ScratchpadNote.titlePlaceholder ? "Scratchpad" : note.title
        panel.nameFieldStringValue = suggestion.hasSuffix(".md") ? suggestion : "\(suggestion).md"

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Data(text.utf8).write(to: url, options: .atomic)
            } catch {
                NSAlert(error: error).runModal()
                return
            }
            ClearlyAppDelegate.shared?.ensureRegularAndActivate()
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        }
    }

    // MARK: - Delete with undo

    func deleteCurrent() {
        guard let note = currentNote else { return }
        deleteNote(note)
    }

    func deleteNote(_ note: ScratchpadNote) {
        var replacementID: ScratchpadNote.ID?
        let nextSelection: ScratchpadNote? = {
            let remaining = store.notes.filter { $0.id != note.id }
            return remaining.first
        }()
        guard let token = store.delete(note) else { return }

        if currentNoteID == note.id {
            if let next = nextSelection {
                currentNoteID = next.id
                store.touchOpened(next)
            } else {
                let created = store.create()
                currentNoteID = created.id
                replacementID = created.id
            }
        }
        deleteUndo.present(token: token) { [weak self] in
            guard let self else { return }
            if let replacementID,
               let replacement = self.store.notes.first(where: { $0.id == replacementID }),
               self.store.loadText(for: replacement).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                _ = self.store.delete(replacement)
                if self.currentNoteID == replacementID {
                    self.currentNoteID = nil
                }
            }
            self.store.restore(token)
            self.currentNoteID = token.url
        }
    }

    func runRetentionSweep() {
        let protectedURLs = currentNoteID.map { Set([$0]) } ?? Set<URL>()
        store.runRetentionSweep(preserving: protectedURLs)
        if let id = currentNoteID, store.notes.first(where: { $0.id == id }) == nil {
            currentNoteID = store.notes.first?.id
        }
    }

    // MARK: - Window construction

    private func ensureWindow() {
        if let win = window {
            if !win.isVisible { positionTopRightIfUnsaved(win) }
            return
        }
        let rootView = ScratchpadShellView()
            .environment(self)
            .environment(store)
            .environment(deleteUndo)
        let controller = NSHostingController(rootView: rootView)
        controller.sizingOptions = .minSize

        let win = ScratchpadPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable,
                        .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        win.contentViewController = controller
        win.title = " "
        win.level = .floating
        win.isFloatingPanel = true
        win.becomesKeyOnlyIfNeeded = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 420, height: 320)
        win.contentMinSize = NSSize(width: 420, height: 320)
        win.titleVisibility = .hidden
        win.titlebarSeparatorStyle = .none
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true

        let delegate = WindowDelegate()
        win.delegate = delegate
        windowDelegate = delegate

        window = win

        win.setFrameAutosaveName("ClearlyScratchpadWindow_v2")
        positionTopRightIfUnsaved(win)
    }

    private static let defaultScratchpadContentSize = NSSize(width: 480, height: 560)

    private func positionTopRightIfUnsaved(_ win: NSPanel) {
        if win.setFrameUsingName("ClearlyScratchpadWindow_v2") { return }
        win.setContentSize(Self.defaultScratchpadContentSize)
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = win.frame.size
        let frame = NSRect(
            x: visible.maxX - size.width - 24,
            y: visible.maxY - size.height - 24,
            width: size.width,
            height: size.height
        )
        win.setFrame(frame, display: false)
    }

    // MARK: - NSWindowDelegate

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            ScratchpadStore.shared.flushPendingWrites()
        }
    }
}
