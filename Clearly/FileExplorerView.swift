import SwiftUI
import ClearlyCore
import AppKit

// MARK: - Sidebar wrapper (SwiftUI)

struct FileExplorerView: View {
    @Bindable var workspace: WorkspaceManager

    var body: some View {
        VStack(spacing: 0) {
            if workspace.locations.isEmpty && workspace.pinnedFiles.isEmpty && workspace.recentFiles.isEmpty && workspace.openDocuments.isEmpty {
                FileExplorerEmptyView(workspace: workspace)
            } else {
                FileExplorerOutlineView(workspace: workspace)
            }
        }
        .background(Color.clear)
    }
}

// MARK: - Empty state

struct FileExplorerEmptyView: View {
    var workspace: WorkspaceManager
    @State private var iconOpacity: Double = 0.15

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(.quaternary)
                    .opacity(iconOpacity)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                            iconOpacity = 0.30
                        }
                    }
                Text("No Locations")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Add a folder to browse your Markdown files")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                Button("Add Location…") {
                    workspace.showOpenPanel()
                }
                .controlSize(.small)
                .tint(.accentColor)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .position(x: geo.size.width / 2, y: geo.size.height * 0.4)
        }
    }
}

// MARK: - Custom row view with full drawing control

class ClearlySidebarRowView: NSTableRowView {
    /// Optional tint color from a parent folder's color
    var folderTintColor: NSColor?

    override var isEmphasized: Bool {
        get { true }
        set { }
    }

    // Prevent AppKit from changing text to white on selection
    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        return .normal
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if let tint = folderTintColor {
            tint.withAlphaComponent(isDark ? 0.20 : 0.12).setFill()
        } else {
            NSColor.black.withAlphaComponent(isDark ? 0.15 : 0.06).setFill()
        }
        let selectionRect = bounds.insetBy(dx: 4, dy: 1)
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6)
        path.fill()
    }

    override func drawBackground(in dirtyRect: NSRect) {
        // Tinted backgrounds are drawn at the outline view level as grouped rects
    }

    override func drawSeparator(in dirtyRect: NSRect) {
        // No row separators
    }
}

// MARK: - Custom outline view (flatten indentation for leaf section children)

class FlatSectionOutlineView: NSOutlineView {
    weak var colorCoordinator: FileExplorerOutlineView.Coordinator?

    override func drawBackground(inClipRect clipRect: NSRect) {
        super.drawBackground(inClipRect: clipRect)
        guard let coordinator = colorCoordinator else { return }

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let visibleRows = rows(in: clipRect)
        guard visibleRows.length > 0 else { return }

        // Group consecutive rows by their folder color
        var currentColor: NSColor?
        var groupStartRow = -1

        func flushGroup(endRow: Int) {
            guard let color = currentColor, groupStartRow >= 0 else { return }
            let startRect = rect(ofRow: groupStartRow)
            let endRect = rect(ofRow: endRow)
            let groupRect = NSRect(
                x: startRect.origin.x,
                y: startRect.origin.y,
                width: startRect.width,
                height: endRect.maxY - startRect.origin.y - 1
            ).insetBy(dx: 4, dy: 0)
            color.withAlphaComponent(isDark ? 0.06 : 0.04).setFill()
            let path = NSBezierPath(roundedRect: groupRect, xRadius: 6, yRadius: 6)
            path.fill()
        }

        for row in visibleRows.location..<(visibleRows.location + visibleRows.length) {
            guard let item = self.item(atRow: row) as? FileExplorerOutlineView.OutlineItem,
                  let url = item.url else {
                flushGroup(endRow: row - 1)
                currentColor = nil
                groupStartRow = -1
                continue
            }

            let rowColor = coordinator.folderColorForURL(url)

            if rowColor != currentColor {
                if currentColor != nil {
                    flushGroup(endRow: row - 1)
                }
                currentColor = rowColor
                groupStartRow = rowColor != nil ? row : -1
            }
        }
        // Flush final group
        if currentColor != nil {
            flushGroup(endRow: visibleRows.location + visibleRows.length - 1)
        }
    }

    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        var frame = super.frameOfCell(atColumn: column, row: row)
        let level = self.level(forRow: row)

        // The system adds indentation (level * indentationPerLevel) + disclosure button width (~18px).
        // We hide the disclosure button, so reclaim that 18px.
        // For level 0 (sections) and level 1 (top folders/recents): flush left.
        // For level 2+: indent relative to level 1.
        let disclosureSpace: CGFloat = 18
        let systemIndent = CGFloat(level) * self.indentationPerLevel + disclosureSpace
        let desiredIndent: CGFloat = level <= 1 ? 0 : CGFloat(level - 1) * self.indentationPerLevel
        let shift = systemIndent - desiredIndent
        frame.origin.x -= shift
        frame.size.width += shift
        return frame
    }

    // Hide the disclosure triangles — folders expand/collapse on click
    override func makeView(withIdentifier identifier: NSUserInterfaceItemIdentifier, owner: Any?) -> NSView? {
        if identifier == NSOutlineView.disclosureButtonIdentifier {
            // Must return an NSButton (AppKit sends button messages to it)
            // Make it truly invisible: transparent, no bezel, zero size
            let btn = NSButton(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
            btn.identifier = identifier
            btn.isBordered = false
            btn.isTransparent = true
            btn.title = ""
            btn.image = nil
            btn.alphaValue = 0
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.widthAnchor.constraint(equalToConstant: 0).isActive = true
            btn.heightAnchor.constraint(equalToConstant: 0).isActive = true
            return btn
        }
        return super.makeView(withIdentifier: identifier, owner: owner)
    }

    // Click on expandable rows toggles expansion
    override func mouseDown(with event: NSEvent) {
        let startPoint = convert(event.locationInWindow, from: nil)
        let clickedRow = self.row(at: startPoint)

        // Always let super handle tracking (enables drag initiation)
        super.mouseDown(with: event)

        // If clicked on expandable row and didn't drag, toggle expansion
        if clickedRow >= 0, let item = self.item(atRow: clickedRow),
           self.dataSource?.outlineView?(self, isItemExpandable: item) ?? false {
            let endPoint = convert(NSApp.currentEvent?.locationInWindow ?? event.locationInWindow, from: nil)
            if hypot(endPoint.x - startPoint.x, endPoint.y - startPoint.y) < 5 {
                if isItemExpanded(item) { collapseItem(item) } else { expandItem(item) }
            }
        }
    }

    // Allow buttons inside cell views to receive clicks
    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        if responder is NSButton { return true }
        return super.validateProposedFirstResponder(responder, for: event)
    }
}

// MARK: - NSOutlineView wrapper

struct FileExplorerOutlineView: NSViewRepresentable {
    var workspace: WorkspaceManager

    func makeCoordinator() -> Coordinator {
        Coordinator(workspace: workspace)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let outlineView = FlatSectionOutlineView()
        outlineView.headerView = nil
        outlineView.style = .plain
        outlineView.indentationPerLevel = 14
        outlineView.rowSizeStyle = .custom
        outlineView.rowHeight = 28
        outlineView.selectionHighlightStyle = .regular
        outlineView.floatsGroupRows = false
        outlineView.intercellSpacing = NSSize(width: 0, height: 0)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        column.isEditable = false
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator

        // Built-in expansion state persistence
        outlineView.autosaveName = "ClearlySidebarOutline"
        outlineView.autosaveExpandedItems = true

        // Context menu
        let menu = NSMenu()
        menu.delegate = context.coordinator
        outlineView.menu = menu

        // Drag and drop
        outlineView.registerForDraggedTypes([.fileURL])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)

        // Double-click does nothing extra (single-click selects)
        outlineView.doubleAction = nil

        scrollView.documentView = outlineView
        context.coordinator.outlineView = outlineView

        // Expand locations by default
        DispatchQueue.main.async {
            context.coordinator.reloadAndExpand()
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.workspace = workspace
        context.coordinator.reloadIfNeeded()
    }

    // MARK: - Outline items

    /// Root-level sections
    enum Section: String, CaseIterable {
        case pinned = "PINNED"
        case locations = "LOCATIONS"
        case recents = "RECENTS"
        case tags = "TAGS"
    }

    /// Wrapper for items in the outline view
    final class OutlineItem: NSObject {
        enum Kind {
            case section(Section)
            case location(BookmarkedLocation)
            case fileNode(FileNode)
            case pinnedFile(URL)
            case recentFile(URL)
            case openDocument(OpenDocument)
            case tagEntry(tag: String, count: Int)
        }
        var kind: Kind

        init(_ kind: Kind) {
            self.kind = kind
        }

        var url: URL? {
            switch kind {
            case .section: return nil
            case .location(let loc): return loc.url
            case .fileNode(let node): return node.url
            case .pinnedFile(let url): return url
            case .recentFile(let url): return url
            case .openDocument(let doc): return doc.fileURL
            case .tagEntry: return nil
            }
        }

        var isDirectory: Bool {
            switch kind {
            case .fileNode(let node): return node.isDirectory
            case .location: return true
            case .section, .pinnedFile, .recentFile, .openDocument, .tagEntry: return false
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate, NSPopoverDelegate {
        var workspace: WorkspaceManager
        weak var outlineView: NSOutlineView?

        // Cache outline items to maintain identity for NSOutlineView
        private var sectionItems: [Section: OutlineItem] = [:]
        private var locationItems: [UUID: OutlineItem] = [:]
        private var nodeItems: [URL: OutlineItem] = [:]
        private var pinnedItems: [URL: OutlineItem] = [:]
        private var recentItems: [URL: OutlineItem] = [:]
        private var openDocItems: [UUID: OutlineItem] = [:]
        private var tagItems: [String: OutlineItem] = [:]
        private var cachedTags: [(tag: String, count: Int)] = []
        private var lastVaultRevision: Int = 0
        private var hadPinnedBefore = false
        private var hadTagsBefore = false

        // Track state to avoid redundant reloads (updateNSView fires on every SwiftUI render)
        private var lastLocationCount = 0
        private var lastPinnedCount = 0
        private var lastRecentCount = 0
        private var lastOpenDocCount = 0
        private var lastLocationTreeHash = 0
        private var lastActiveDocumentID: UUID?
        private var lastCurrentFileURL: URL?
        private var hasLoadedOnce = false

        // Prevent re-entrant selection changes
        private var isProgrammaticSelection = false
        private weak var clearRecentsButton: NSButton?

        init(workspace: WorkspaceManager) {
            self.workspace = workspace
            super.init()
            for section in Section.allCases {
                sectionItems[section] = OutlineItem(.section(section))
            }
        }

        func item(for section: Section) -> OutlineItem {
            sectionItems[section]!
        }

        func item(for location: BookmarkedLocation) -> OutlineItem {
            if let existing = locationItems[location.id] {
                existing.kind = .location(location)
                return existing
            }
            let item = OutlineItem(.location(location))
            locationItems[location.id] = item
            return item
        }

        func item(for node: FileNode) -> OutlineItem {
            if let existing = nodeItems[node.url] {
                existing.kind = .fileNode(node)
                return existing
            }
            let item = OutlineItem(.fileNode(node))
            nodeItems[node.url] = item
            return item
        }

        func item(forPinned url: URL) -> OutlineItem {
            if let existing = pinnedItems[url] {
                return existing
            }
            let item = OutlineItem(.pinnedFile(url))
            pinnedItems[url] = item
            return item
        }

        func item(for recentURL: URL) -> OutlineItem {
            if let existing = recentItems[recentURL] {
                return existing
            }
            let item = OutlineItem(.recentFile(recentURL))
            recentItems[recentURL] = item
            return item
        }

        func item(for doc: OpenDocument) -> OutlineItem {
            if let existing = openDocItems[doc.id] {
                existing.kind = .openDocument(doc)
                return existing
            }
            let item = OutlineItem(.openDocument(doc))
            openDocItems[doc.id] = item
            return item
        }

        func item(forTag tag: String, count: Int) -> OutlineItem {
            if let existing = tagItems[tag] {
                existing.kind = .tagEntry(tag: tag, count: count)
                return existing
            }
            let item = OutlineItem(.tagEntry(tag: tag, count: count))
            tagItems[tag] = item
            return item
        }

        // MARK: - Folder Color Lookup

        /// Finds the folder color for a URL by checking the URL and its parent folders
        func folderColorForURL(_ url: URL) -> NSColor? {
            // Check the URL's own path first
            if let colorName = workspace.folderColors[url.path],
               let color = Theme.folderColor(named: colorName) {
                return color
            }
            // Walk up parent directories to find an inherited color
            var parent = url.deletingLastPathComponent()
            for _ in 0..<20 { // safety limit
                if let colorName = workspace.folderColors[parent.path],
                   let color = Theme.folderColor(named: colorName) {
                    return color
                }
                let next = parent.deletingLastPathComponent()
                if next.path == parent.path { break }
                parent = next
            }
            return nil
        }

        // MARK: - Change Detection

        private func dataDidChange() -> Bool {
            let locCount = workspace.locations.count
            let pinCount = workspace.pinnedFiles.count
            let recCount = workspace.recentFiles.count
            let openCount = workspace.openDocuments.count
            let treeHash = workspace.treeRevision
            let activeID = workspace.activeDocumentID
            let vaultRev = workspace.vaultIndexRevision
            let currentURL = workspace.currentFileURL

            let changed = locCount != lastLocationCount
                || pinCount != lastPinnedCount
                || recCount != lastRecentCount
                || openCount != lastOpenDocCount
                || treeHash != lastLocationTreeHash
                || activeID != lastActiveDocumentID
                || vaultRev != lastVaultRevision
                || currentURL != lastCurrentFileURL

            if vaultRev != lastVaultRevision {
                refreshCachedTags()
            }

            lastLocationCount = locCount
            lastPinnedCount = pinCount
            lastRecentCount = recCount
            lastOpenDocCount = openCount
            lastLocationTreeHash = treeHash
            lastActiveDocumentID = activeID
            lastVaultRevision = vaultRev
            lastCurrentFileURL = currentURL

            return changed
        }

        private func refreshCachedTags() {
            var merged: [String: Int] = [:]
            for index in workspace.activeVaultIndexes {
                for entry in index.allTags() {
                    merged[entry.tag, default: 0] += entry.count
                }
            }
            cachedTags = merged.map { (tag: $0.key, count: $0.value) }
                .sorted { $0.tag < $1.tag }
        }

        // MARK: - Reload

        func reloadAndExpand() {
            guard let outlineView else { return }
            refreshCachedTags()
            outlineView.reloadData()
            // autosaveExpandedItems restores expansion state automatically.
            // On first ever launch (no saved state), expand everything.
            if !hasLoadedOnce {
                hasLoadedOnce = true
                let hasAutosave = UserDefaults.standard.object(forKey: "NSOutlineView Items ClearlySidebarOutline") != nil
                if !hasAutosave {
                    outlineView.expandItem(nil, expandChildren: true)
                }
            }
            selectCurrentFile()
            hadPinnedBefore = !workspace.pinnedFiles.isEmpty
            hadTagsBefore = !cachedTags.isEmpty
            _ = dataDidChange()
        }

        func reloadIfNeeded() {
            guard dataDidChange() else { return }
            guard let outlineView else { return }
            let pinnedJustAppeared = !hadPinnedBefore && !workspace.pinnedFiles.isEmpty
            hadPinnedBefore = !workspace.pinnedFiles.isEmpty
            let tagsJustAppeared = !hadTagsBefore && !cachedTags.isEmpty
            hadTagsBefore = !cachedTags.isEmpty
            outlineView.reloadData()
            // autosaveExpandedItems handles restoration automatically
            if pinnedJustAppeared {
                outlineView.expandItem(item(for: .pinned))
            }
            if tagsJustAppeared {
                outlineView.expandItem(item(for: .tags))
            }
            selectCurrentFile()
            clearRecentsButton?.isHidden = workspace.recentFiles.isEmpty
        }

        func selectCurrentFile() {
            guard let outlineView, let activeID = workspace.activeDocumentID else {
                outlineView?.deselectAll(nil)
                return
            }
            let activeURL = workspace.currentFileURL
            isProgrammaticSelection = true
            defer { isProgrammaticSelection = false }
            for row in 0..<outlineView.numberOfRows {
                guard let outlineItem = outlineView.item(atRow: row) as? OutlineItem else { continue }
                switch outlineItem.kind {
                case .openDocument(let doc) where doc.id == activeID:
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    return
                case .pinnedFile(let url) where url == activeURL:
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    return
                case .recentFile(let url) where url == activeURL:
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    return
                case .fileNode(let node) where !node.isDirectory && node.url == activeURL:
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    return
                default:
                    break
                }
            }
        }

        // MARK: - Autosave Expansion (data source methods)

        func outlineView(_ outlineView: NSOutlineView, persistentObjectForItem item: Any?) -> Any? {
            guard let outlineItem = item as? OutlineItem else { return nil }
            switch outlineItem.kind {
            case .section(let section): return "section:\(section.rawValue)"
            case .location(let loc): return "location:\(loc.url.path)"
            case .fileNode(let node): return "node:\(node.url.path)"
            case .pinnedFile(let url): return "pinned:\(url.path)"
            case .recentFile(let url): return "recent:\(url.path)"
            case .openDocument(let doc): return "openDoc:\(doc.id.uuidString)"
            case .tagEntry(let tag, _): return "tag:\(tag)"
            }
        }

        func outlineView(_ outlineView: NSOutlineView, itemForPersistentObject object: Any) -> Any? {
            guard let key = object as? String else { return nil }

            if key.hasPrefix("section:") {
                let name = String(key.dropFirst("section:".count))
                if let section = Section(rawValue: name) { return item(for: section) }
            } else if key.hasPrefix("location:") {
                let path = String(key.dropFirst("location:".count))
                if let loc = workspace.locations.first(where: { $0.url.path == path }) {
                    return item(for: loc)
                }
            } else if key.hasPrefix("pinned:") {
                let path = String(key.dropFirst("pinned:".count))
                let url = URL(fileURLWithPath: path)
                if workspace.pinnedFiles.contains(url) { return item(forPinned: url) }
            } else if key.hasPrefix("node:") {
                let path = String(key.dropFirst("node:".count))
                let url = URL(fileURLWithPath: path)
                // Find this node in any location's tree
                func findNode(in nodes: [FileNode]) -> FileNode? {
                    for node in nodes {
                        if node.url == url { return node }
                        if let children = node.children, let found = findNode(in: children) { return found }
                    }
                    return nil
                }
                for loc in workspace.locations {
                    if let node = findNode(in: loc.fileTree) { return item(for: node) }
                }
            } else if key.hasPrefix("tag:") {
                let tag = String(key.dropFirst("tag:".count))
                if let entry = cachedTags.first(where: { $0.tag == tag }) {
                    return item(forTag: entry.tag, count: entry.count)
                }
            }
            return nil
        }

        // MARK: - Drag and Drop

        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard let outlineItem = item as? OutlineItem else { return nil }
            switch outlineItem.kind {
            case .fileNode(let node):
                return node.url as NSURL
            default:
                return nil
            }
        }

        private func draggedURLs(from info: NSDraggingInfo) -> [URL] {
            guard let items = info.draggingPasteboard.pasteboardItems else { return [] }
            return items.compactMap { item in
                guard let str = item.string(forType: .fileURL) else { return nil }
                return URL(string: str)
            }
        }

        func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            // Determine the actual drop target folder
            let target: OutlineItem
            if index == NSOutlineViewDropOnItemIndex,
               let proposed = item as? OutlineItem, proposed.isDirectory {
                target = proposed
            } else {
                // Proposed "between" rows — retarget to the folder row under the cursor
                let point = outlineView.convert(info.draggingLocation, from: nil)
                let row = outlineView.row(at: point)
                guard row >= 0,
                      let hovered = outlineView.item(atRow: row) as? OutlineItem,
                      hovered.isDirectory else { return [] }
                target = hovered
            }

            guard let targetURL = target.url else { return [] }
            let urls = draggedURLs(from: info)
            guard !urls.isEmpty else { return [] }

            for sourceURL in urls {
                // Prevent dropping item into its current parent (no-op)
                if sourceURL.deletingLastPathComponent().path == targetURL.path { return [] }
                // Prevent dropping a folder into itself or a descendant
                if targetURL.path == sourceURL.path || targetURL.path.hasPrefix(sourceURL.path + "/") { return [] }
            }

            outlineView.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex)
            return .move
        }

        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
            guard let target = item as? OutlineItem, let targetURL = target.url else { return false }
            let urls = draggedURLs(from: info)
            guard !urls.isEmpty else { return false }

            var success = true
            for sourceURL in urls {
                if workspace.moveItem(at: sourceURL, into: targetURL) == nil {
                    success = false
                }
            }
            return success
        }

        // MARK: - Data Source

        /// Sections to display — hides PINNED when empty, hides TAGS when no tags exist.
        private var visibleSections: [Section] {
            Section.allCases.filter {
                switch $0 {
                case .pinned: return !workspace.pinnedFiles.isEmpty
                case .tags: return !cachedTags.isEmpty
                default: return true
                }
            }
        }

        /// Open documents shown at the top of RECENTS.
        private var recentSectionOpenDocs: [OpenDocument] {
            workspace.openDocuments
        }

        /// Recent files that are not already visible as open documents, capped so total recents ≤ 5.
        private var recentHistoryFiles: [URL] {
            let openFileURLs = Set(workspace.openDocuments.compactMap(\.fileURL))
            let history = workspace.recentFiles.filter { !openFileURLs.contains($0) }
            let remaining = max(0, 5 - recentSectionOpenDocs.count)
            return Array(history.prefix(remaining))
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let item = item as? OutlineItem else {
                return visibleSections.count
            }
            switch item.kind {
            case .section(.pinned):
                return workspace.pinnedFiles.count
            case .section(.locations):
                return workspace.locations.count
            case .section(.tags):
                return cachedTags.count
            case .section(.recents):
                return recentSectionOpenDocs.count + recentHistoryFiles.count
            case .location(let loc):
                return loc.fileTree.count
            case .fileNode(let node):
                return node.children?.count ?? 0
            case .pinnedFile, .recentFile, .openDocument, .tagEntry:
                return 0
            }
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let item = item as? OutlineItem else {
                return self.item(for: visibleSections[index])
            }
            switch item.kind {
            case .section(.pinned):
                return self.item(forPinned: workspace.pinnedFiles[index])
            case .section(.locations):
                return self.item(for: workspace.locations[index])
            case .section(.tags):
                let entry = cachedTags[index]
                return self.item(forTag: entry.tag, count: entry.count)
            case .section(.recents):
                let openDocs = recentSectionOpenDocs
                if index < openDocs.count {
                    return self.item(for: openDocs[index])
                }
                return self.item(for: recentHistoryFiles[index - openDocs.count])
            case .location(let loc):
                return self.item(for: loc.fileTree[index])
            case .fileNode(let node):
                return self.item(for: node.children![index])
            case .pinnedFile, .recentFile, .openDocument, .tagEntry:
                fatalError("Leaf items have no children")
            }
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let item = item as? OutlineItem else { return false }
            switch item.kind {
            case .section(.pinned): return true
            case .section(.locations): return true
            case .section(.tags): return true
            case .section(.recents): return true
            case .location: return true
            case .fileNode(let node): return node.isDirectory
            case .pinnedFile, .recentFile, .openDocument, .tagEntry: return false
            }
        }

        // MARK: - Delegate

        func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
            return false
        }

        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            let rowView = ClearlySidebarRowView()
            if let outlineItem = item as? OutlineItem, let url = outlineItem.url {
                rowView.folderTintColor = folderColorForURL(url)
            }
            return rowView
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            guard let item = item as? OutlineItem else { return false }
            switch item.kind {
            case .section: return false
            case .location: return false
            case .fileNode(let node): return !node.isDirectory
            case .pinnedFile: return true
            case .recentFile: return true
            case .openDocument: return true
            case .tagEntry: return true
            }
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let outlineItem = item as? OutlineItem else { return nil }

            let isSection = { if case .section = outlineItem.kind { return true } else { return false } }()
            let cellID = NSUserInterfaceItemIdentifier(isSection ? "SectionCell" : "FileCell")
            let cell: NSTableCellView
            if let reused = outlineView.makeView(withIdentifier: cellID, owner: nil) as? NSTableCellView {
                cell = reused
            } else {
                cell = NSTableCellView()
                cell.identifier = cellID

                let textField = NSTextField(labelWithString: "")
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.lineBreakMode = .byTruncatingTail
                textField.maximumNumberOfLines = 1
                textField.cell?.truncatesLastVisibleLine = true
                cell.addSubview(textField)
                cell.textField = textField

                if isSection {
                    NSLayoutConstraint.activate([
                        textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                        textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    ])
                } else {
                    let imageView = NSImageView()
                    imageView.translatesAutoresizingMaskIntoConstraints = false
                    cell.addSubview(imageView)
                    cell.imageView = imageView

                    NSLayoutConstraint.activate([
                        imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                        imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                        imageView.widthAnchor.constraint(equalToConstant: 18),
                        imageView.heightAnchor.constraint(equalToConstant: 18),
                        textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                        textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    ])
                }
            }

            // Reset cell state for reuse
            let addButtonTag = 999
            cell.viewWithTag(addButtonTag)?.removeFromSuperview()
            cell.textField?.font = .systemFont(ofSize: 12)
            cell.textField?.textColor = .labelColor
            cell.alphaValue = 1.0

            switch outlineItem.kind {
            case .section(let section):
                let sectionAttr = NSMutableAttributedString(string: section.rawValue)
                sectionAttr.addAttributes([
                    .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .kern: 0
                ], range: NSRange(location: 0, length: sectionAttr.length))
                cell.textField?.attributedStringValue = sectionAttr

                if section == .locations {
                    let addBtn = NSButton(frame: .zero)
                    addBtn.bezelStyle = .inline
                    addBtn.isBordered = false
                    let btnConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
                    addBtn.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "Add Location")?.withSymbolConfiguration(btnConfig)
                    addBtn.imagePosition = .imageOnly
                    addBtn.toolTip = "Add Location (⌘O)"
                    addBtn.target = self
                    addBtn.action = #selector(addLocationAction(_:))
                    addBtn.tag = addButtonTag
                    addBtn.translatesAutoresizingMaskIntoConstraints = false
                    addBtn.contentTintColor = .tertiaryLabelColor
                    cell.addSubview(addBtn)
                    NSLayoutConstraint.activate([
                        addBtn.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -7),
                        addBtn.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                        addBtn.widthAnchor.constraint(equalToConstant: 14),
                        addBtn.heightAnchor.constraint(equalToConstant: 14),
                    ])
                } else if section == .recents {
                    let clearBtn = NSButton(frame: .zero)
                    clearBtn.bezelStyle = .inline
                    clearBtn.isBordered = false
                    let clearConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold)
                    clearBtn.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Clear Recents")?.withSymbolConfiguration(clearConfig)
                    clearBtn.imagePosition = .imageOnly
                    clearBtn.toolTip = "Clear Recents"
                    clearBtn.target = self
                    clearBtn.action = #selector(clearRecentsAction(_:))
                    clearBtn.tag = addButtonTag
                    clearBtn.translatesAutoresizingMaskIntoConstraints = false
                    clearBtn.contentTintColor = .tertiaryLabelColor
                    clearBtn.isHidden = workspace.recentFiles.isEmpty
                    self.clearRecentsButton = clearBtn
                    cell.addSubview(clearBtn)
                    NSLayoutConstraint.activate([
                        clearBtn.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -7),
                        clearBtn.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                        clearBtn.widthAnchor.constraint(equalToConstant: 10),
                        clearBtn.heightAnchor.constraint(equalToConstant: 10),
                    ])
                }

            case .location(let loc):
                cell.textField?.attributedStringValue = NSAttributedString(
                    string: loc.name,
                    attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor]
                )
                let locIcon = workspace.folderIcons[loc.url.path] ?? "folder"
                let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                cell.imageView?.image = NSImage(systemSymbolName: locIcon, accessibilityDescription: "Folder")?.withSymbolConfiguration(config)
                cell.imageView?.symbolConfiguration = config
                let locColor = folderColorForURL(loc.url)
                cell.imageView?.contentTintColor = locColor ?? .secondaryLabelColor
                cell.imageView?.isHidden = false

            case .fileNode(let node):
                cell.textField?.attributedStringValue = NSAttributedString(
                    string: node.name,
                    attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
                )
                let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                let nodeColor = folderColorForURL(node.url)
                if node.isDirectory {
                    let nodeIcon = workspace.folderIcons[node.url.path] ?? "folder"
                    cell.imageView?.image = NSImage(systemSymbolName: nodeIcon, accessibilityDescription: "Folder")?.withSymbolConfiguration(config)
                    cell.imageView?.symbolConfiguration = config
                    cell.imageView?.contentTintColor = nodeColor ?? .secondaryLabelColor
                } else {
                    let isPinned = workspace.isPinned(node.url)
                    let iconName = isPinned ? "pin" : "doc.text"
                    cell.imageView?.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "File")?.withSymbolConfiguration(config)
                    cell.imageView?.symbolConfiguration = config
                    cell.imageView?.contentTintColor = isPinned ? .controlAccentColor : (nodeColor?.withAlphaComponent(0.6) ?? .tertiaryLabelColor)
                }
                cell.imageView?.isHidden = false
                if node.isHidden { cell.alphaValue = 0.5 }

            case .pinnedFile(let url):
                let filename = url.lastPathComponent
                let parentName = url.deletingLastPathComponent().lastPathComponent
                let attributed = NSMutableAttributedString(
                    string: filename,
                    attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
                )
                attributed.append(NSAttributedString(
                    string: "  \(parentName)",
                    attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.tertiaryLabelColor]
                ))
                cell.textField?.font = .systemFont(ofSize: 12)
                cell.textField?.attributedStringValue = attributed
                let pinnedConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                cell.imageView?.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Pinned")?.withSymbolConfiguration(pinnedConfig)
                cell.imageView?.symbolConfiguration = pinnedConfig
                cell.imageView?.contentTintColor = .controlAccentColor
                cell.imageView?.isHidden = false

            case .recentFile(let url):
                let filename = url.lastPathComponent
                let parentName = url.deletingLastPathComponent().lastPathComponent
                let attributed = NSMutableAttributedString(
                    string: filename,
                    attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
                )
                attributed.append(NSAttributedString(
                    string: "  \(parentName)",
                    attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.tertiaryLabelColor]
                ))
                cell.textField?.font = .systemFont(ofSize: 12)
                cell.textField?.attributedStringValue = attributed
                let recentConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                cell.imageView?.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "File")?.withSymbolConfiguration(recentConfig)
                cell.imageView?.symbolConfiguration = recentConfig
                cell.imageView?.contentTintColor = .tertiaryLabelColor
                cell.imageView?.isHidden = false

            case .openDocument(let doc):
                cell.textField?.attributedStringValue = NSAttributedString(
                    string: doc.displayName,
                    attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
                )
                let docConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                let iconName = doc.isUntitled ? "doc.text" : "doc.text.fill"
                cell.imageView?.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Document")?.withSymbolConfiguration(docConfig)
                cell.imageView?.symbolConfiguration = docConfig
                cell.imageView?.contentTintColor = doc.isUntitled ? .secondaryLabelColor : .tertiaryLabelColor
                cell.imageView?.isHidden = false

            case .tagEntry(let tag, let count):
                let tagAttr = NSMutableAttributedString(
                    string: tag,
                    attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
                )
                tagAttr.append(NSAttributedString(
                    string: "  \(count)",
                    attributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.tertiaryLabelColor]
                ))
                cell.textField?.attributedStringValue = tagAttr
                let tagConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
                cell.imageView?.image = NSImage(systemSymbolName: "number", accessibilityDescription: "Tag")?.withSymbolConfiguration(tagConfig)
                cell.imageView?.symbolConfiguration = tagConfig
                cell.imageView?.contentTintColor = .secondaryLabelColor
                cell.imageView?.isHidden = false
            }

            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            // Skip when we're programmatically setting selection (e.g. after reload)
            guard !isProgrammaticSelection else { return }
            guard let outlineView else { return }
            let row = outlineView.selectedRow
            guard row >= 0, let outlineItem = outlineView.item(atRow: row) as? OutlineItem else { return }

            let cmdHeld = NSEvent.modifierFlags.contains(.command)

            switch outlineItem.kind {
            case .openDocument(let doc):
                workspace.switchToDocument(doc.id)
            case .fileNode(let node) where !node.isDirectory:
                if cmdHeld {
                    workspace.openFileInNewTab(at: node.url)
                } else {
                    workspace.openFile(at: node.url)
                }
            case .pinnedFile(let url):
                if cmdHeld {
                    workspace.openFileInNewTab(at: url)
                } else {
                    workspace.openFile(at: url)
                }
            case .recentFile(let url):
                if cmdHeld {
                    workspace.openFileInNewTab(at: url)
                } else {
                    workspace.openFile(at: url)
                }
            case .tagEntry(let tag, _):
                NotificationCenter.default.post(
                    name: .init("ClearlyFilterByTag"),
                    object: nil,
                    userInfo: ["tag": tag]
                )
            default:
                break
            }
        }

        // MARK: - Context Menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outlineView else { return }

            let clickedRow = outlineView.clickedRow
            guard clickedRow >= 0, let outlineItem = outlineView.item(atRow: clickedRow) as? OutlineItem else {
                // Clicked on empty space
                menu.addItem(NSMenuItem(title: "Add Location…", action: #selector(addLocationAction(_:)), keyEquivalent: ""))
                menu.items.last?.target = self
                return
            }

            switch outlineItem.kind {
            case .section(.locations):
                menu.addItem(NSMenuItem(title: "Add Location…", action: #selector(addLocationAction(_:)), keyEquivalent: ""))
                menu.items.last?.target = self

            case .location(let loc):
                let newFileItem = NSMenuItem(title: "New File…", action: #selector(newFileInFolderAction(_:)), keyEquivalent: "")
                newFileItem.representedObject = loc.url
                newFileItem.target = self
                menu.addItem(newFileItem)

                let newFolderItem = NSMenuItem(title: "New Folder…", action: #selector(newFolderAction(_:)), keyEquivalent: "")
                newFolderItem.representedObject = loc.url
                newFolderItem.target = self
                menu.addItem(newFolderItem)

                menu.addItem(.separator())

                let changeIconItem = NSMenuItem(title: "Customize…", action: #selector(changeIconAction(_:)), keyEquivalent: "")
                changeIconItem.representedObject = loc.url
                changeIconItem.target = self
                menu.addItem(changeIconItem)

                menu.addItem(.separator())

                let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(revealInFinderAction(_:)), keyEquivalent: "")
                revealItem.representedObject = loc.url
                revealItem.target = self
                menu.addItem(revealItem)

                menu.addItem(.separator())

                let removeItem = NSMenuItem(title: "Remove Location", action: #selector(removeLocationAction(_:)), keyEquivalent: "")
                removeItem.representedObject = loc.id
                removeItem.target = self
                menu.addItem(removeItem)

            case .fileNode(let node):
                let parentURL = node.url.deletingLastPathComponent()

                if node.isDirectory {
                    let newFileItem = NSMenuItem(title: "New File…", action: #selector(newFileInFolderAction(_:)), keyEquivalent: "")
                    newFileItem.representedObject = node.url
                    newFileItem.target = self
                    menu.addItem(newFileItem)

                    let newFolderItem = NSMenuItem(title: "New Folder…", action: #selector(newFolderAction(_:)), keyEquivalent: "")
                    newFolderItem.representedObject = node.url
                    newFolderItem.target = self
                    menu.addItem(newFolderItem)

                    menu.addItem(.separator())

                    let changeIconItem = NSMenuItem(title: "Customize…", action: #selector(changeIconAction(_:)), keyEquivalent: "")
                    changeIconItem.representedObject = node.url
                    changeIconItem.target = self
                    menu.addItem(changeIconItem)

                    menu.addItem(.separator())
                } else {
                    let openTabItem = NSMenuItem(title: "Open in New Tab", action: #selector(openInNewTabAction(_:)), keyEquivalent: "")
                    openTabItem.representedObject = node.url
                    openTabItem.target = self
                    menu.addItem(openTabItem)

                    let newFileItem = NSMenuItem(title: "New File…", action: #selector(newFileInFolderAction(_:)), keyEquivalent: "")
                    newFileItem.representedObject = parentURL
                    newFileItem.target = self
                    menu.addItem(newFileItem)

                    menu.addItem(.separator())
                }

                let renameItem = NSMenuItem(title: "Rename…", action: #selector(renameAction(_:)), keyEquivalent: "")
                renameItem.representedObject = node.url
                renameItem.target = self
                menu.addItem(renameItem)

                let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(revealInFinderAction(_:)), keyEquivalent: "")
                revealItem.representedObject = node.url
                revealItem.target = self
                menu.addItem(revealItem)

                if !node.isDirectory {
                    let copyItem = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "")
                    copyItem.submenu = CopyActions.copySubmenu(for: node.url, target: self)
                    menu.addItem(copyItem)
                }

                if !node.isDirectory {
                    menu.addItem(.separator())
                    let pinTitle = workspace.isPinned(node.url) ? "Unpin" : "Pin"
                    let pinItem = NSMenuItem(title: pinTitle, action: #selector(togglePinAction(_:)), keyEquivalent: "d")
                    pinItem.keyEquivalentModifierMask = [.command]
                    pinItem.representedObject = node.url
                    pinItem.target = self
                    menu.addItem(pinItem)
                }

                menu.addItem(.separator())

                let deleteItem = NSMenuItem(title: "Move to Trash", action: #selector(moveToTrashAction(_:)), keyEquivalent: "")
                deleteItem.representedObject = node.url
                deleteItem.target = self
                menu.addItem(deleteItem)

            case .pinnedFile(let url):
                let openTabItem = NSMenuItem(title: "Open in New Tab", action: #selector(openInNewTabAction(_:)), keyEquivalent: "")
                openTabItem.representedObject = url
                openTabItem.target = self
                menu.addItem(openTabItem)

                let unpinItem = NSMenuItem(title: "Unpin", action: #selector(togglePinAction(_:)), keyEquivalent: "d")
                unpinItem.keyEquivalentModifierMask = [.command]
                unpinItem.representedObject = url
                unpinItem.target = self
                menu.addItem(unpinItem)

                menu.addItem(.separator())

                let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(revealInFinderAction(_:)), keyEquivalent: "")
                revealItem.representedObject = url
                revealItem.target = self
                menu.addItem(revealItem)

                let copyItem = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "")
                copyItem.submenu = CopyActions.copySubmenu(for: url, target: self)
                menu.addItem(copyItem)

            case .recentFile(let url):
                let openTabItem = NSMenuItem(title: "Open in New Tab", action: #selector(openInNewTabAction(_:)), keyEquivalent: "")
                openTabItem.representedObject = url
                openTabItem.target = self
                menu.addItem(openTabItem)

                let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(revealInFinderAction(_:)), keyEquivalent: "")
                revealItem.representedObject = url
                revealItem.target = self
                menu.addItem(revealItem)

                let copyItem = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "")
                copyItem.submenu = CopyActions.copySubmenu(for: url, target: self)
                menu.addItem(copyItem)

                menu.addItem(.separator())
                let pinTitle = workspace.isPinned(url) ? "Unpin" : "Pin"
                let pinItem = NSMenuItem(title: pinTitle, action: #selector(togglePinAction(_:)), keyEquivalent: "p")
                pinItem.keyEquivalentModifierMask = [.command, .shift]
                pinItem.representedObject = url
                pinItem.target = self
                menu.addItem(pinItem)

            case .openDocument(let doc):
                if doc.isUntitled {
                    let saveItem = NSMenuItem(title: "Save As…", action: #selector(saveOpenDocAction(_:)), keyEquivalent: "")
                    saveItem.representedObject = doc.id
                    saveItem.target = self
                    menu.addItem(saveItem)
                    menu.addItem(.separator())
                } else if let url = doc.fileURL {
                    let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(revealInFinderAction(_:)), keyEquivalent: "")
                    revealItem.representedObject = url
                    revealItem.target = self
                    menu.addItem(revealItem)

                    let copyItem = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "")
                    copyItem.submenu = CopyActions.copySubmenu(for: url, target: self)
                    menu.addItem(copyItem)

                    menu.addItem(.separator())

                    let pinTitle = workspace.isPinned(url) ? "Unpin" : "Pin"
                    let pinItem = NSMenuItem(title: pinTitle, action: #selector(togglePinAction(_:)), keyEquivalent: "d")
                    pinItem.keyEquivalentModifierMask = [.command]
                    pinItem.representedObject = url
                    pinItem.target = self
                    menu.addItem(pinItem)

                    menu.addItem(.separator())
                }

                let closeItem = NSMenuItem(title: "Close", action: #selector(closeOpenDocAction(_:)), keyEquivalent: "")
                closeItem.representedObject = doc.id
                closeItem.target = self
                menu.addItem(closeItem)

            case .section(.pinned):
                break

            case .section(.recents):
                if !workspace.recentFiles.isEmpty {
                    let clearItem = NSMenuItem(title: "Clear Recents", action: #selector(clearRecentsAction(_:)), keyEquivalent: "")
                    clearItem.target = self
                    menu.addItem(clearItem)
                }

            case .section(.tags):
                break

            case .tagEntry:
                break
            }
        }

        // MARK: - Context Menu Actions

        @objc func clearRecentsAction(_ sender: Any) {
            // Close all open documents (prompts to save dirty ones)
            let docIDs = workspace.openDocuments.map(\.id)
            for id in docIDs {
                if !workspace.closeDocument(id) {
                    return // User cancelled a save prompt — abort
                }
            }

            workspace.clearRecents()
            recentItems.removeAll()
            openDocItems.removeAll()
            reloadAndExpand()
        }

        @objc func togglePinAction(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            workspace.togglePin(url)
            pinnedItems.removeAll()
            reloadAndExpand()
            if !workspace.pinnedFiles.isEmpty {
                outlineView?.expandItem(item(for: .pinned))
            }
        }

        @objc func addLocationAction(_ sender: NSMenuItem) {
            workspace.showOpenPanel()
        }

        @objc func newFileInFolderAction(_ sender: NSMenuItem) {
            guard let folderURL = sender.representedObject as? URL else { return }
            let alert = NSAlert()
            alert.messageText = "New File"
            alert.informativeText = "Enter a name for the new file:"
            alert.addButton(withTitle: "Create")
            alert.addButton(withTitle: "Cancel")

            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            input.stringValue = "Untitled.md"
            alert.accessoryView = input
            alert.window.initialFirstResponder = input

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let name = input.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }

            if let fileURL = workspace.createFile(named: name, in: folderURL) {
                workspace.openFile(at: fileURL)
            }
        }

        @objc func newFolderAction(_ sender: NSMenuItem) {
            guard let parentURL = sender.representedObject as? URL else { return }
            let alert = NSAlert()
            alert.messageText = "New Folder"
            alert.informativeText = "Enter a name for the new folder:"
            alert.addButton(withTitle: "Create")
            alert.addButton(withTitle: "Cancel")

            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            input.stringValue = "New Folder"
            alert.accessoryView = input
            alert.window.initialFirstResponder = input

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let name = input.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }

            _ = workspace.createFolder(named: name, in: parentURL)
        }

        @objc func renameAction(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            let alert = NSAlert()
            alert.messageText = "Rename"
            alert.informativeText = "Enter a new name:"
            alert.addButton(withTitle: "Rename")
            alert.addButton(withTitle: "Cancel")

            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            input.stringValue = url.lastPathComponent
            alert.accessoryView = input
            alert.window.initialFirstResponder = input

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            let newName = input.stringValue.trimmingCharacters(in: .whitespaces)
            guard !newName.isEmpty, newName != url.lastPathComponent else { return }

            _ = workspace.renameItem(at: url, to: newName)
        }

        @objc func revealInFinderAction(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            workspace.revealInFinder(url)
        }

        @objc func moveToTrashAction(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            let alert = NSAlert()
            alert.messageText = "Move to Trash?"
            alert.informativeText = "Are you sure you want to move \"\(url.lastPathComponent)\" to the Trash?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Move to Trash")
            alert.addButton(withTitle: "Cancel")

            guard alert.runModal() == .alertFirstButtonReturn else { return }
            _ = workspace.deleteItem(at: url)
        }

        @objc func removeLocationAction(_ sender: NSMenuItem) {
            guard let locationID = sender.representedObject as? UUID,
                  let location = workspace.locations.first(where: { $0.id == locationID }) else { return }
            workspace.removeLocation(location)
        }

        @objc func openInNewTabAction(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            workspace.openFileInNewTab(at: url)
        }

        @objc func closeOpenDocAction(_ sender: NSMenuItem) {
            guard let docID = sender.representedObject as? UUID else { return }
            workspace.closeDocument(docID)
        }

        @objc func saveOpenDocAction(_ sender: NSMenuItem) {
            guard let docID = sender.representedObject as? UUID else { return }
            // Switch to the document first, then save (triggers NSSavePanel for untitled)
            guard workspace.switchToDocument(docID) else { return }
            workspace.saveCurrentFile()
        }

        // MARK: - Copy Actions

        @objc func copyFilePathAction(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            CopyActions.copyFilePath(url)
        }

        @objc func copyFileNameAction(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            CopyActions.copyFileName(url)
        }

        @objc func copyMarkdownAction(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            guard let text = workspace.textForCopy(at: url) else { return }
            CopyActions.copyMarkdown(text)
        }

        @objc func copyHTMLAction(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            guard let text = workspace.textForCopy(at: url) else { return }
            CopyActions.copyHTML(text)
        }

        @objc func copyRichTextAction(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            guard let text = workspace.textForCopy(at: url) else { return }
            CopyActions.copyRichText(text)
        }

        @objc func copyPlainTextAction(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            guard let text = workspace.textForCopy(at: url) else { return }
            CopyActions.copyPlainText(text)
        }

        // MARK: - Folder Icon Actions

        private var iconPopover: NSPopover?

        @objc func changeIconAction(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL,
                  let outlineView else { return }

            let clickedRow = outlineView.clickedRow
            guard clickedRow >= 0 else { return }

            let rowRect = outlineView.rect(ofRow: clickedRow)
            let currentIcon = workspace.folderIcons[url.path]
            let currentColor = workspace.folderColors[url.path]

            let pickerState = IconPickerState(icon: currentIcon, color: currentColor)
            let picker = IconPickerView(
                state: pickerState,
                onSelectIcon: { [weak self] selectedIcon in
                    guard let self else { return }
                    if let selectedIcon {
                        self.workspace.setFolderIcon(selectedIcon, for: url.path)
                    } else {
                        self.workspace.removeFolderIcon(for: url.path)
                    }
                    self.outlineView?.reloadData()
                    self.selectCurrentFile()
                },
                onSelectColor: { [weak self] selectedColor in
                    guard let self else { return }
                    if let selectedColor {
                        self.workspace.setFolderColor(selectedColor, for: url.path)
                    } else {
                        self.workspace.removeFolderColor(for: url.path)
                    }
                    self.outlineView?.reloadData()
                    self.selectCurrentFile()
                }
            )

            let hostingController = NSHostingController(rootView: picker)
            let popover = NSPopover()
            popover.contentViewController = hostingController
            popover.behavior = .transient
            popover.delegate = self
            iconPopover = popover
            popover.show(relativeTo: rowRect, of: outlineView, preferredEdge: .maxX)
        }

        func popoverDidClose(_ notification: Notification) {
            iconPopover = nil
            outlineView?.reloadData()
        }

        @objc func resetIconAction(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL,
                  let outlineView else { return }
            workspace.removeFolderIcon(for: url.path)
            outlineView.reloadData()
        }
    }
}
