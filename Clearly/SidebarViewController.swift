import AppKit
import SwiftUI

/// Pure AppKit sidebar view controller — no SwiftUI hosting view for the main content.
/// The outline view is built directly in AppKit so the background is fully controlled.
@MainActor
class SidebarViewController: NSViewController {
    let workspace: WorkspaceManager
    private var outlineCoordinator: FileExplorerOutlineView.Coordinator?
    private var scrollView: NSScrollView?
    private var emptyHostingView: NSHostingView<FileExplorerEmptyView>?
    private var updateTimer: Timer?

    init(workspace: WorkspaceManager) {
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let container = ClearlySidebarBackgroundView()
        container.wantsLayer = true
        container.layer?.backgroundColor = Theme.sidebarBackground.cgColor
        self.view = container

        setupOutlineView()
        setupEmptyState()
        updateVisibility()

        // Poll for workspace changes (simple and reliable)
        updateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.outlineCoordinator?.reloadIfNeeded()
                self?.updateVisibility()
            }
        }
    }

    private func setupOutlineView() {
        let coordinator = FileExplorerOutlineView.Coordinator(workspace: workspace)
        self.outlineCoordinator = coordinator

        let sv = NSScrollView()
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = true
        sv.drawsBackground = false
        sv.translatesAutoresizingMaskIntoConstraints = false

        let outlineView = FlatSectionOutlineView()
        outlineView.headerView = nil
        outlineView.style = .plain
        outlineView.indentationPerLevel = 10
        outlineView.rowSizeStyle = .custom
        outlineView.rowHeight = 28
        outlineView.selectionHighlightStyle = .regular
        outlineView.floatsGroupRows = false
        outlineView.intercellSpacing = NSSize(width: 0, height: 0)
        outlineView.backgroundColor = .clear

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.isEditable = false
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.dataSource = coordinator
        outlineView.delegate = coordinator

        outlineView.autosaveName = "ClearlySidebarOutline"
        outlineView.autosaveExpandedItems = true

        let menu = NSMenu()
        menu.delegate = coordinator
        outlineView.menu = menu
        outlineView.doubleAction = nil

        sv.documentView = outlineView
        coordinator.outlineView = outlineView
        outlineView.colorCoordinator = coordinator

        // Make everything transparent so the container background shows through
        sv.contentView.drawsBackground = false
        sv.contentView.wantsLayer = true
        sv.contentView.layer?.backgroundColor = NSColor.clear.cgColor

        // Add content insets: top for traffic lights, left/right for breathing room
        sv.contentInsets = NSEdgeInsets(top: 52, left: 6, bottom: 0, right: 6)
        sv.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: -6)
        sv.automaticallyAdjustsContentInsets = false

        view.addSubview(sv)
        self.scrollView = sv

        NSLayoutConstraint.activate([
            sv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sv.topAnchor.constraint(equalTo: view.topAnchor),
            sv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Opaque header that covers the traffic lights area so content doesn't scroll behind it
        let headerCover = ClearlySidebarBackgroundView()
        headerCover.wantsLayer = true
        headerCover.layer?.backgroundColor = Theme.sidebarBackground.cgColor
        headerCover.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerCover, positioned: .above, relativeTo: sv)
        NSLayoutConstraint.activate([
            headerCover.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerCover.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerCover.topAnchor.constraint(equalTo: view.topAnchor),
            headerCover.heightAnchor.constraint(equalToConstant: 52),
        ])

        DispatchQueue.main.async {
            coordinator.reloadAndExpand()
        }
    }

    private func setupEmptyState() {
        let hostingView = NSHostingView(rootView: FileExplorerEmptyView(workspace: workspace))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        // Force transparent so container background shows through
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        view.addSubview(hostingView)
        self.emptyHostingView = hostingView

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func updateVisibility() {
        let isEmpty = workspace.locations.isEmpty && workspace.recentFiles.isEmpty && workspace.openDocuments.isEmpty
        scrollView?.isHidden = isEmpty
        emptyHostingView?.isHidden = !isEmpty
    }

    deinit {
        updateTimer?.invalidate()
    }
}

/// NSView subclass that maintains sidebar background across appearance changes
class ClearlySidebarBackgroundView: NSView {
    override func updateLayer() {
        layer?.backgroundColor = Theme.sidebarBackground.cgColor
    }

    override var wantsUpdateLayer: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        layer?.backgroundColor = Theme.sidebarBackground.cgColor
    }
}
