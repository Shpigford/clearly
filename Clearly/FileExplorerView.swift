import SwiftUI
import AppKit

// MARK: - Sidebar wrapper (SwiftUI)

struct FileExplorerView: View {
    @Bindable var workspace: WorkspaceManager

    var body: some View {
        VStack(spacing: 0) {
            if workspace.locations.isEmpty && workspace.recentFiles.isEmpty && workspace.openDocuments.isEmpty {
                FileExplorerEmptyView(workspace: workspace)
            } else {
                FileExplorerOutlineView(workspace: workspace)
            }
        }
    }
}

// MARK: - Empty state

struct FileExplorerEmptyView: View {
    var workspace: WorkspaceManager

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(.quaternary)
            Text("No Locations")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Add a folder to browse your markdown files")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Add Location…") {
                workspace.showOpenPanel()
            }
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Row view that keeps blue selection when editor has focus

class AlwaysEmphasizedRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set { }
    }
}

// MARK: - Custom outline view (flatten indentation for leaf section children)

class FlatSectionOutlineView: NSOutlineView {
    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        var frame = super.frameOfCell(atColumn: column, row: row)
        let level = self.level(forRow: row)
        // Only adjust level-1 items that are not expandable (recents, open docs)
        let item = self.item(atRow: row)
        let expandable = self.dataSource?.outlineView?(self, isItemExpandable: item!) ?? false
        if level == 1 && !expandable {
            let indent = CGFloat(level) * self.indentationPerLevel
            frame.origin.x -= indent
            frame.size.width += indent
        }
        return frame
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
        outlineView.style = .sourceList
        outlineView.indentationPerLevel = 10
        outlineView.rowSizeStyle = .small
        outlineView.selectionHighlightStyle = .sourceList
        outlineView.floatsGroupRows = false

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
        case locations = "LOCATIONS"
        case recents = "RECENTS"
    }

    /// Wrapper for items in the outline view
    final class OutlineItem: NSObject {
        enum Kind {
            case section(Section)
            case location(BookmarkedLocation)
            case fileNode(FileNode)
            case recentFile(URL)
            case openDocument(OpenDocument)
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
            case .recentFile(let url): return url
            case .openDocument(let doc): return doc.fileURL
            }
        }

        var isDirectory: Bool {
            switch kind {
            case .fileNode(let node): return node.isDirectory
            case .location: return true
            case .section, .recentFile, .openDocument: return false
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        var workspace: WorkspaceManager
        weak var outlineView: NSOutlineView?

        // Cache outline items to maintain identity for NSOutlineView
        private var sectionItems: [Section: OutlineItem] = [:]
        private var locationItems: [UUID: OutlineItem] = [:]
        private var nodeItems: [URL: OutlineItem] = [:]
        private var recentItems: [URL: OutlineItem] = [:]
        private var openDocItems: [UUID: OutlineItem] = [:]

        // Track state to avoid redundant reloads (updateNSView fires on every SwiftUI render)
        private var lastLocationCount = 0
        private var lastRecentCount = 0
        private var lastOpenDocCount = 0
        private var lastLocationTreeHash = 0
        private var lastActiveDocumentID: UUID?
        private var hasLoadedOnce = false

        // Prevent re-entrant selection changes
        private var isProgrammaticSelection = false

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

        // MARK: - Change Detection

        private func dataDidChange() -> Bool {
            let locCount = workspace.locations.count
            let recCount = workspace.recentFiles.count
            let openCount = workspace.openDocuments.count
            let treeHash = workspace.locations.reduce(0) { $0 ^ $1.fileTree.hashValue }
            let activeID = workspace.activeDocumentID

            let changed = locCount != lastLocationCount
                || recCount != lastRecentCount
                || openCount != lastOpenDocCount
                || treeHash != lastLocationTreeHash
                || activeID != lastActiveDocumentID

            lastLocationCount = locCount
            lastRecentCount = recCount
            lastOpenDocCount = openCount
            lastLocationTreeHash = treeHash
            lastActiveDocumentID = activeID

            return changed
        }

        // MARK: - Reload

        func reloadAndExpand() {
            guard let outlineView else { return }
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
            _ = dataDidChange()
        }

        func reloadIfNeeded() {
            guard dataDidChange() else { return }
            guard let outlineView else { return }
            outlineView.reloadData()
            // autosaveExpandedItems handles restoration automatically
            selectCurrentFile()
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
            case .recentFile(let url): return "recent:\(url.path)"
            case .openDocument(let doc): return "openDoc:\(doc.id.uuidString)"
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
            }
            return nil
        }

        // MARK: - Data Source

        /// Untitled open documents shown at the top of RECENTS.
        private var untitledDocs: [OpenDocument] {
            workspace.openDocuments.filter { $0.isUntitled }
        }

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let item = item as? OutlineItem else {
                return Section.allCases.count
            }
            switch item.kind {
            case .section(.locations):
                return workspace.locations.count
            case .section(.recents):
                return untitledDocs.count + workspace.recentFiles.count
            case .location(let loc):
                return loc.fileTree.count
            case .fileNode(let node):
                return node.children?.count ?? 0
            case .recentFile, .openDocument:
                return 0
            }
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let item = item as? OutlineItem else {
                return self.item(for: Section.allCases[index])
            }
            switch item.kind {
            case .section(.locations):
                return self.item(for: workspace.locations[index])
            case .section(.recents):
                let untitled = untitledDocs
                if index < untitled.count {
                    return self.item(for: untitled[index])
                }
                return self.item(for: workspace.recentFiles[index - untitled.count])
            case .location(let loc):
                return self.item(for: loc.fileTree[index])
            case .fileNode(let node):
                return self.item(for: node.children![index])
            case .recentFile, .openDocument:
                fatalError("Leaf items have no children")
            }
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let item = item as? OutlineItem else { return false }
            switch item.kind {
            case .section(.locations): return true
            case .section(.recents): return true
            case .location: return true
            case .fileNode(let node): return node.isDirectory
            case .recentFile, .openDocument: return false
            }
        }

        // MARK: - Delegate

        func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
            return false
        }

        func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
            return AlwaysEmphasizedRowView()
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            guard let item = item as? OutlineItem else { return false }
            switch item.kind {
            case .section: return false
            case .location: return false
            case .fileNode(let node): return !node.isDirectory
            case .recentFile: return true
            case .openDocument: return true
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
                        textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                        textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    ])
                } else {
                    let imageView = NSImageView()
                    imageView.translatesAutoresizingMaskIntoConstraints = false
                    cell.addSubview(imageView)
                    cell.imageView = imageView

                    NSLayoutConstraint.activate([
                        imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                        imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                        imageView.widthAnchor.constraint(equalToConstant: 16),
                        imageView.heightAnchor.constraint(equalToConstant: 16),
                        textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
                        textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                        textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    ])
                }
            }

            // Remove any previously added action button
            let addButtonTag = 999
            cell.viewWithTag(addButtonTag)?.removeFromSuperview()

            switch outlineItem.kind {
            case .section(let section):
                cell.textField?.stringValue = section.rawValue
                cell.textField?.font = .systemFont(ofSize: 11, weight: .semibold)

                if section == .locations {
                    let addBtn = NSButton(frame: .zero)
                    addBtn.bezelStyle = .inline
                    addBtn.isBordered = false
                    addBtn.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Location")
                    addBtn.imagePosition = .imageOnly
                    addBtn.toolTip = "Add Location (⌘O)"
                    addBtn.target = self
                    addBtn.action = #selector(addLocationAction(_:))
                    addBtn.tag = addButtonTag
                    addBtn.translatesAutoresizingMaskIntoConstraints = false
                    addBtn.contentTintColor = .secondaryLabelColor
                    cell.addSubview(addBtn)
                    NSLayoutConstraint.activate([
                        addBtn.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                        addBtn.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                        addBtn.widthAnchor.constraint(equalToConstant: 16),
                        addBtn.heightAnchor.constraint(equalToConstant: 16),
                    ])
                }

            case .location(let loc):
                cell.textField?.stringValue = loc.name
                cell.textField?.font = .systemFont(ofSize: 13, weight: .medium)
                cell.imageView?.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "Folder")
                cell.imageView?.contentTintColor = .secondaryLabelColor
                cell.imageView?.isHidden = false

            case .fileNode(let node):
                cell.textField?.stringValue = node.name
                cell.textField?.font = .systemFont(ofSize: 13)
                if node.isDirectory {
                    cell.imageView?.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Folder")
                    cell.imageView?.contentTintColor = .secondaryLabelColor
                } else {
                    cell.imageView?.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "File")
                    cell.imageView?.contentTintColor = .tertiaryLabelColor
                }
                cell.imageView?.isHidden = false

            case .recentFile(let url):
                let filename = url.lastPathComponent
                let parentName = url.deletingLastPathComponent().lastPathComponent
                let attributed = NSMutableAttributedString(
                    string: filename,
                    attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
                )
                attributed.append(NSAttributedString(
                    string: "  \(parentName)",
                    attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.tertiaryLabelColor]
                ))
                cell.textField?.attributedStringValue = attributed
                cell.imageView?.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "File")
                cell.imageView?.contentTintColor = .tertiaryLabelColor
                cell.imageView?.isHidden = false

            case .openDocument(let doc):
                let prefix = doc.isDirty ? "● " : ""
                cell.textField?.stringValue = prefix + doc.displayName
                cell.textField?.font = .systemFont(ofSize: 13)
                let iconName = doc.isUntitled ? "doc.text" : "doc.text.fill"
                cell.imageView?.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Document")
                cell.imageView?.contentTintColor = doc.isUntitled ? .secondaryLabelColor : .tertiaryLabelColor
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

            switch outlineItem.kind {
            case .openDocument(let doc):
                workspace.switchToDocument(doc.id)
            case .fileNode(let node) where !node.isDirectory:
                workspace.openFile(at: node.url)
            case .recentFile(let url):
                workspace.openFile(at: url)
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
                } else {
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

                menu.addItem(.separator())

                let deleteItem = NSMenuItem(title: "Move to Trash", action: #selector(moveToTrashAction(_:)), keyEquivalent: "")
                deleteItem.representedObject = node.url
                deleteItem.target = self
                menu.addItem(deleteItem)

            case .recentFile(let url):
                let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(revealInFinderAction(_:)), keyEquivalent: "")
                revealItem.representedObject = url
                revealItem.target = self
                menu.addItem(revealItem)

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
                    menu.addItem(.separator())
                }

                let closeItem = NSMenuItem(title: "Close", action: #selector(closeOpenDocAction(_:)), keyEquivalent: "")
                closeItem.representedObject = doc.id
                closeItem.target = self
                menu.addItem(closeItem)

            case .section(.recents):
                break
            }
        }

        // MARK: - Context Menu Actions

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
    }
}
