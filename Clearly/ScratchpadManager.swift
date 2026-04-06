import AppKit
import SwiftUI
import UniformTypeIdentifiers
import KeyboardShortcuts

struct Scratchpad: Identifiable {
    let id = UUID()
    var text: String = ""

    var displayTitle: String {
        let firstLine = text.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        if firstLine.isEmpty { return "Empty Scratchpad" }
        return String(firstLine.prefix(30))
    }
}

@MainActor
@Observable
final class ScratchpadManager {
    static let shared = ScratchpadManager()

    var scratchpads: [Scratchpad] = []
    private var windows: [UUID: NSWindow] = [:]
    private var delegates: [UUID: WindowDelegate] = [:]

    private init() {
        KeyboardShortcuts.onKeyUp(for: .newScratchpad) { [weak self] in
            Task { @MainActor in
                self?.createScratchpad()
            }
        }
    }

    private var nextCascadeOffset: Int = 0

    func createScratchpad() {
        let pad = Scratchpad()
        let padID = pad.id
        scratchpads.append(pad)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 360),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Scratchpad"
        window.level = .floating
        window.minSize = NSSize(width: 300, height: 200)
        window.isReleasedWhenClosed = false
        window.canHide = false

        // Minimal chrome — Raycast Notes style
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.backgroundColor = Theme.backgroundColor.withAlphaComponent(0.88)
        window.isOpaque = false
        window.standardWindowButton(.closeButton)?.superview?.alphaValue = 0

        let binding = Binding<String>(
            get: { [weak self] in
                self?.scratchpads.first(where: { $0.id == padID })?.text ?? ""
            },
            set: { [weak self] newValue in
                guard let self, let idx = self.scratchpads.firstIndex(where: { $0.id == padID }) else { return }
                self.scratchpads[idx].text = newValue
            }
        )

        let contentView = ScratchpadContentView(text: binding, onSave: { [weak self] in
            self?.saveAsDocument(id: padID)
        })
        window.contentView = NSHostingView(rootView: contentView)

        // Add hover tracking for traffic light buttons (above content so it receives events)
        if let themeFrame = window.contentView?.superview {
            let tracker = TrafficLightTracker(window: window)
            tracker.translatesAutoresizingMaskIntoConstraints = false
            themeFrame.addSubview(tracker)
            NSLayoutConstraint.activate([
                tracker.leadingAnchor.constraint(equalTo: themeFrame.leadingAnchor),
                tracker.trailingAnchor.constraint(equalTo: themeFrame.trailingAnchor),
                tracker.topAnchor.constraint(equalTo: themeFrame.topAnchor),
                tracker.heightAnchor.constraint(equalToConstant: 38),
            ])
        }

        let delegate = WindowDelegate(id: padID) { [weak self] id in
            self?.remove(id: id)
        }
        window.delegate = delegate
        delegates[padID] = delegate
        windows[padID] = window

        // Position top-right with padding, cascade subsequent windows
        if let screen = NSScreen.main {
            let visibleFrame = screen.visibleFrame
            let padding: CGFloat = 24
            let cascadeStep: CGFloat = 30
            let offset = CGFloat(nextCascadeOffset) * cascadeStep
            let origin = NSPoint(
                x: visibleFrame.maxX - 400 - padding - offset,
                y: visibleFrame.maxY - 360 - padding - offset
            )
            window.setFrameOrigin(origin)
            nextCascadeOffset += 1
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func remove(id: UUID) {
        scratchpads.removeAll { $0.id == id }
        windows.removeValue(forKey: id)
        delegates.removeValue(forKey: id)
        if windows.isEmpty { nextCascadeOffset = 0 }
    }

    func focusScratchpad(id: UUID) {
        guard let window = windows[id] else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func saveAsDocument(id: UUID) {
        guard let pad = scratchpads.first(where: { $0.id == id }),
              !pad.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let window = windows[id] else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.daringFireballMarkdown]
        let name = pad.displayTitle
        panel.nameFieldStringValue = name.hasSuffix(".md") ? name : "\(name).md"

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }

            do {
                try pad.text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
                return
            }

            activateDocumentApp()
            NSDocumentController.shared.openDocument(
                withContentsOf: url,
                display: true
            ) { [weak self] _, _, error in
                if let error {
                    let alert = NSAlert(error: error)
                    alert.runModal()
                    return
                }
                Task { @MainActor in
                    self?.windows[id]?.close()
                }
            }
        }
    }

    func closeAll() {
        let ids = Array(windows.keys)
        for id in ids {
            windows[id]?.close()
        }
    }

    // MARK: - Window Delegate

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        let id: UUID
        let onClose: (UUID) -> Void

        init(id: UUID, onClose: @escaping (UUID) -> Void) {
            self.id = id
            self.onClose = onClose
        }

        func windowWillClose(_ notification: Notification) {
            onClose(id)
        }
    }
}

// MARK: - Traffic Light Hover Tracking

private final class TrafficLightTracker: NSView {
    private weak var targetWindow: NSWindow?
    private var trackingArea: NSTrackingArea?

    init(window: NSWindow) {
        self.targetWindow = window
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        setTrafficLightAlpha(1)
    }

    override func mouseExited(with event: NSEvent) {
        setTrafficLightAlpha(0)
    }

    private func setTrafficLightAlpha(_ alpha: CGFloat) {
        guard let window = targetWindow,
              let buttonSuperview = window.standardWindowButton(.closeButton)?.superview else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            buttonSuperview.animator().alphaValue = alpha
        }
    }
}
