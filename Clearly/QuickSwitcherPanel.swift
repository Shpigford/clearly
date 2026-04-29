import AppKit
import ClearlyCore

// MARK: - Quick Switcher File Item

struct QuickSwitcherItem {
    let filename: String       // e.g. "My Note"
    let relativePath: String   // e.g. "folder/My Note.md"
    let fullURL: URL
    let score: Int
    let matchedRanges: [Range<String.Index>]
    let isCreateNew: Bool
    let lineNumber: Int?           // for content matches: line to scroll to
    let contextSnippet: String?    // for content matches: matching line text

    init(filename: String, relativePath: String, fullURL: URL, score: Int,
         matchedRanges: [Range<String.Index>], isCreateNew: Bool,
         lineNumber: Int? = nil, contextSnippet: String? = nil) {
        self.filename = filename
        self.relativePath = relativePath
        self.fullURL = fullURL
        self.score = score
        self.matchedRanges = matchedRanges
        self.isCreateNew = isCreateNew
        self.lineNumber = lineNumber
        self.contextSnippet = contextSnippet
    }

    var isContentMatch: Bool { lineNumber != nil }

    var displayPath: String {
        let dir = (relativePath as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }
}

// MARK: - Quick Switcher Manager

@MainActor
final class QuickSwitcherManager: NSObject {
    static let shared = QuickSwitcherManager()

    private enum TagFilterMode {
        case contains
        case exact(String)
    }

    private var panel: NSPanel?
    private var searchField: NSTextField?
    private var tableView: NSTableView?
    private var scrollView: NSScrollView?
    private var separator: NSBox?

    private var items: [QuickSwitcherItem] = []
    private var allFiles: [(filename: String, path: String, url: URL)] = []
    private var tagFilterMode: TagFilterMode = .contains

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show(withQuery query: String = "") {
        show(withQuery: query, tagFilterMode: .contains)
    }

    func show(tagFilter tag: String) {
        show(withQuery: "#\(tag)", tagFilterMode: .exact(tag))
    }

    private func show(withQuery query: String, tagFilterMode: TagFilterMode) {
        if panel == nil {
            createPanel()
        }
        self.tagFilterMode = tagFilterMode
        refreshFileList()
        searchField?.stringValue = query
        updateResults(query: query)
        positionPanel()
        panel?.makeKeyAndOrderFront(nil)
        searchField?.becomeFirstResponder()
    }

    func dismiss() {
        panel?.orderOut(nil)
    }

    // MARK: - Panel Creation

    private func createPanel() {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 48),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isMovableByWindowBackground = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.delegate = self

        // Rounded visual effect background
        let visualEffect = NSVisualEffectView(frame: panel.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true
        panel.contentView?.addSubview(visualEffect)

        // Container for search + results
        let container = NSView(frame: visualEffect.bounds)
        container.autoresizingMask = [.width, .height]
        visualEffect.addSubview(container)

        // Search field
        let field = NSTextField(frame: .zero)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholderString = "Search notes…"
        field.font = .systemFont(ofSize: 18, weight: .regular)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.cell?.sendsActionOnEndEditing = false
        container.addSubview(field)
        self.searchField = field

        // Separator (hidden until results appear)
        let separator = NSBox(frame: .zero)
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.boxType = .separator
        separator.isHidden = true
        container.addSubview(separator)
        self.separator = separator

        // Table view
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.isEditable = false

        let tableView = NSTableView(frame: .zero)
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 36
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.action = #selector(tableClicked)
        tableView.doubleAction = #selector(tableDoubleClicked)
        tableView.target = self
        self.tableView = tableView

        let scrollView = NSScrollView(frame: .zero)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        container.addSubview(scrollView)
        self.scrollView = scrollView

        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            field.heightAnchor.constraint(equalToConstant: 24),

            separator.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 8),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
        ])

        self.panel = panel
    }

    private func positionPanel() {
        guard let panel else { return }
        let referenceWindow = NSApp.mainWindow ?? NSApp.keyWindow
        let referenceFrame = referenceWindow?.frame ?? (NSScreen.main?.visibleFrame ?? .zero)

        let x = referenceFrame.midX - panel.frame.width / 2
        let y = referenceFrame.maxY - panel.frame.height - referenceFrame.height * 0.15
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Data

    private func refreshFileList() {
        let workspace = WorkspaceManager.shared
        var files: [(filename: String, path: String, url: URL)] = []

        for index in workspace.activeVaultIndexes {
            let rootURL = index.rootURL
            for file in index.allFiles() {
                let fullURL = rootURL.appendingPathComponent(file.path)
                files.append((filename: file.filename, path: file.path, url: fullURL))
            }
        }

        // If no indexes yet, fall back to file tree
        if files.isEmpty {
            for location in workspace.locations {
                collectFiles(from: location.fileTree, rootURL: location.url, into: &files)
            }
        }

        allFiles = files
    }

    private func collectFiles(from nodes: [FileNode], rootURL: URL, into files: inout [(filename: String, path: String, url: URL)]) {
        for node in nodes {
            if node.isDirectory {
                collectFiles(from: node.children ?? [], rootURL: rootURL, into: &files)
            } else {
                let filename = node.url.deletingPathExtension().lastPathComponent
                let relativePath = VaultIndex.relativePath(of: node.url, from: rootURL)
                files.append((filename: filename, path: relativePath, url: node.url))
            }
        }
    }

    private func updateResults(query: String) {
        if query.isEmpty {
            // Show recent files
            let recents = WorkspaceManager.shared.recentFiles
            items = recents.compactMap { url in
                let filename = url.deletingPathExtension().lastPathComponent
                let relativePath: String
                if let vaultRoot = WorkspaceManager.shared.containingVaultRoot(for: url) {
                    relativePath = VaultIndex.relativePath(of: url, from: vaultRoot)
                } else {
                    let parent = url.deletingLastPathComponent().lastPathComponent
                    relativePath = parent.isEmpty ? url.lastPathComponent : "\(parent)/\(url.lastPathComponent)"
                }
                return QuickSwitcherItem(
                    filename: filename,
                    relativePath: relativePath,
                    fullURL: url,
                    score: 100,
                    matchedRanges: [],
                    isCreateNew: false
                )
            }
        } else if query.hasPrefix("#") && query.count >= 2 {
            // Tag filter: show files matching the tag
            let tagQuery = String(query.dropFirst()).lowercased()
            var tagResults: [QuickSwitcherItem] = []
            for index in WorkspaceManager.shared.activeVaultIndexes {
                // Find tags that match the query
                let matchingTags = index.allTags().filter { entry in
                    switch tagFilterMode {
                    case .contains:
                        return entry.tag.lowercased().contains(tagQuery)
                    case .exact(let selectedTag):
                        if selectedTag.lowercased() == tagQuery {
                            return entry.tag.compare(selectedTag, options: [.caseInsensitive]) == .orderedSame
                        }
                        return entry.tag.lowercased().contains(tagQuery)
                    }
                }
                var seenURLs = Set<URL>()
                for tagEntry in matchingTags {
                    for file in index.filesForTag(tag: tagEntry.tag) {
                        let fileURL = index.rootURL.appendingPathComponent(file.path)
                        guard !seenURLs.contains(fileURL) else { continue }
                        seenURLs.insert(fileURL)
                        tagResults.append(QuickSwitcherItem(
                            filename: file.filename,
                            relativePath: file.path,
                            fullURL: fileURL,
                            score: 100,
                            matchedRanges: [],
                            isCreateNew: false,
                            contextSnippet: "#\(tagEntry.tag)"
                        ))
                    }
                }
            }
            tagResults.sort { $0.filename.lowercased() < $1.filename.lowercased() }
            items = tagResults
        } else {
            // Fuzzy match on filenames
            var nameMatches = allFiles.compactMap { file -> QuickSwitcherItem? in
                guard let result = FuzzyMatcher.match(query: query, target: file.filename) else { return nil }
                return QuickSwitcherItem(
                    filename: file.filename,
                    relativePath: file.path,
                    fullURL: file.url,
                    score: result.score,
                    matchedRanges: result.matchedRanges,
                    isCreateNew: false
                )
            }
            .sorted { $0.score > $1.score }
            if nameMatches.count > 20 { nameMatches = Array(nameMatches.prefix(20)) }

            // Content matches via FTS5 (only if query is 2+ chars)
            var contentMatches: [QuickSwitcherItem] = []
            if query.count >= 2 {
                let nameMatchURLs = Set(nameMatches.map(\.fullURL))
                for index in WorkspaceManager.shared.activeVaultIndexes {
                    for group in index.searchFilesGrouped(query: query) {
                        let fileURL = group.vaultRootURL.appendingPathComponent(group.file.path)
                        guard !nameMatchURLs.contains(fileURL) else { continue }
                        let excerpt = group.excerpts.first
                        contentMatches.append(QuickSwitcherItem(
                            filename: group.file.filename,
                            relativePath: group.file.path,
                            fullURL: fileURL,
                            score: 0,
                            matchedRanges: [],
                            isCreateNew: false,
                            lineNumber: excerpt?.lineNumber,
                            contextSnippet: excerpt?.contextLine.trimmingCharacters(in: .whitespaces)
                        ))
                    }
                }
                if contentMatches.count > 30 { contentMatches = Array(contentMatches.prefix(30)) }
            }

            items = nameMatches + contentMatches

            // Add create-on-miss if no results at all
            if items.isEmpty {
                let createName = query.hasSuffix(".md") ? query : "\(query).md"
                items = [QuickSwitcherItem(
                    filename: "Create \(createName)",
                    relativePath: createName,
                    fullURL: URL(fileURLWithPath: "/"),
                    score: -1,
                    matchedRanges: [],
                    isCreateNew: true
                )]
            }
        }

        tableView?.reloadData()
        if !items.isEmpty {
            tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView?.scrollRowToVisible(0)
        }
        resizePanelToFit()
    }

    private static let maxVisibleRows = 10
    // topPad(12) + field(24) + gap(8) + separator(1) + gap(4)
    private static let searchAreaHeight: CGFloat = 49

    private func resizePanelToFit() {
        guard let panel, let tableView else { return }

        let hasResults = !items.isEmpty
        separator?.isHidden = !hasResults
        scrollView?.isHidden = !hasResults

        let totalHeight: CGFloat
        if hasResults {
            // Ask the table for its actual content height
            tableView.tile()
            let lastVisible = min(items.count, Self.maxVisibleRows) - 1
            let tableHeight = tableView.rect(ofRow: lastVisible).maxY
            totalHeight = Self.searchAreaHeight + tableHeight + 6
        } else {
            totalHeight = 48
        }

        var frame = panel.frame
        let delta = totalHeight - frame.height
        frame.origin.y -= delta
        frame.size.height = totalHeight
        panel.setFrame(frame, display: true, animate: false)
    }

    // MARK: - Actions

    private func openSelectedItem() {
        guard let tableView, tableView.selectedRow >= 0, tableView.selectedRow < items.count else { return }
        let item = items[tableView.selectedRow]

        if item.isCreateNew {
            if let location = WorkspaceManager.shared.locations.first {
                if let fileURL = WorkspaceManager.shared.createFile(named: item.relativePath, in: location.url) {
                    WorkspaceManager.shared.openFile(at: fileURL)
                }
            }
        } else {
            WorkspaceManager.shared.openFile(at: item.fullURL)
            if let line = item.lineNumber {
                let currentMode = WorkspaceManager.shared.currentViewMode
                let notificationName: Notification.Name = currentMode == .preview
                    ? .scrollPreviewToLine
                    : .scrollEditorToLine
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    NotificationCenter.default.post(
                        name: notificationName,
                        object: nil,
                        userInfo: ["line": line]
                    )
                }
            }
        }

        dismiss()
    }

    @objc private func tableClicked() {
        guard let tableView, tableView.clickedRow >= 0 else { return }
        openSelectedItem()
    }

    @objc private func tableDoubleClicked() {
        openSelectedItem()
    }
}

// MARK: - NSWindowDelegate

extension QuickSwitcherManager: NSWindowDelegate {
    nonisolated func windowDidResignKey(_ notification: Notification) {
        MainActor.assumeIsolated {
            dismiss()
        }
    }
}

// MARK: - NSTextFieldDelegate

extension QuickSwitcherManager: NSTextFieldDelegate {
    nonisolated func controlTextDidChange(_ obj: Notification) {
        MainActor.assumeIsolated {
            let query = searchField?.stringValue ?? ""
            updateResults(query: query)
        }
    }

    nonisolated func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        return MainActor.assumeIsolated {
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                moveSelection(by: 1)
                return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                moveSelection(by: -1)
                return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                openSelectedItem()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                dismiss()
                return true
            }
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        guard let tableView, !items.isEmpty else { return }
        let current = tableView.selectedRow
        let next = max(0, min(items.count - 1, current + delta))
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }
}

// MARK: - NSTableViewDataSource

extension QuickSwitcherManager: NSTableViewDataSource {
    nonisolated func numberOfRows(in tableView: NSTableView) -> Int {
        MainActor.assumeIsolated {
            items.count
        }
    }
}

// MARK: - NSTableViewDelegate

extension QuickSwitcherManager: NSTableViewDelegate {
    nonisolated func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        MainActor.assumeIsolated {
            guard row < items.count else { return nil }
            let item = items[row]

            if item.isContentMatch {
                let cellID = NSUserInterfaceItemIdentifier("QuickSwitcherContentCell")
                let cell: QuickSwitcherContentCellView
                if let reused = tableView.makeView(withIdentifier: cellID, owner: nil) as? QuickSwitcherContentCellView {
                    cell = reused
                } else {
                    cell = QuickSwitcherContentCellView()
                    cell.identifier = cellID
                }
                cell.configure(with: item)
                return cell
            } else {
                let cellID = NSUserInterfaceItemIdentifier("QuickSwitcherCell")
                let cell: QuickSwitcherCellView
                if let reused = tableView.makeView(withIdentifier: cellID, owner: nil) as? QuickSwitcherCellView {
                    cell = reused
                } else {
                    cell = QuickSwitcherCellView()
                    cell.identifier = cellID
                }
                cell.configure(with: item)
                return cell
            }
        }
    }

    nonisolated func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        MainActor.assumeIsolated {
            guard row < items.count else { return 36 }
            return items[row].isContentMatch ? 52 : 36
        }
    }

    nonisolated func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        QuickSwitcherRowView()
    }
}

// MARK: - Cell View

private class QuickSwitcherCellView: NSView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(nameLabel)

        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(pathLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            pathLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(with item: QuickSwitcherItem) {
        // Icon
        if item.isCreateNew {
            iconView.image = NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: "Create")
            iconView.contentTintColor = Theme.accentColor
        } else {
            iconView.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Document")
            iconView.contentTintColor = .tertiaryLabelColor
        }

        // Name with highlighted matches
        let nameString = NSMutableAttributedString(string: item.filename, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ])

        for range in item.matchedRanges {
            let nsRange = NSRange(range, in: item.filename)
            nameString.addAttributes([
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: Theme.accentColor,
            ], range: nsRange)
        }

        nameLabel.attributedStringValue = nameString

        // Path
        let displayPath = item.displayPath
        if displayPath.isEmpty {
            pathLabel.stringValue = ""
        } else {
            pathLabel.attributedStringValue = NSAttributedString(string: displayPath, attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ])
        }
    }
}

// MARK: - Content Match Cell View (two-line: filename + snippet)

private class QuickSwitcherContentCellView: NSView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let snippetLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(nameLabel)

        snippetLabel.translatesAutoresizingMaskIntoConstraints = false
        snippetLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.maximumNumberOfLines = 1
        snippetLabel.cell?.truncatesLastVisibleLine = true
        snippetLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(snippetLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            snippetLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            snippetLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            snippetLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
        ])
    }

    func configure(with item: QuickSwitcherItem) {
        iconView.image = NSImage(systemSymbolName: "text.magnifyingglass", accessibilityDescription: "Content match")
        iconView.contentTintColor = .tertiaryLabelColor

        // Filename + path
        let nameAttr = NSMutableAttributedString(string: item.filename, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ])
        let displayPath = item.displayPath
        if !displayPath.isEmpty {
            nameAttr.append(NSAttributedString(string: "  \(displayPath)", attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]))
        }
        nameLabel.attributedStringValue = nameAttr

        // Snippet (markdown stripped)
        let raw = item.contextSnippet ?? ""
        let stripped = Self.stripMarkdown(raw)
        let truncated = String(stripped.prefix(120))
        snippetLabel.attributedStringValue = NSAttributedString(string: truncated, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    private static func stripMarkdown(_ text: String) -> String {
        var s = text
        // Headings
        s = s.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
        // Bold/italic markers
        s = s.replacingOccurrences(of: #"\*{1,3}|_{1,3}"#, with: "", options: .regularExpression)
        // Strikethrough
        s = s.replacingOccurrences(of: "~~", with: "")
        // Inline code
        s = s.replacingOccurrences(of: "`", with: "")
        // Links: [text](url) → text
        s = s.replacingOccurrences(of: #"\[([^\]]*)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)
        // Images: ![alt](url) → alt
        s = s.replacingOccurrences(of: #"!\[([^\]]*)\]\([^\)]*\)"#, with: "$1", options: .regularExpression)
        // Wiki-links: [[target|alias]] → alias, [[target]] → target
        s = s.replacingOccurrences(of: #"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]"#, with: "$1", options: .regularExpression)
        // HTML tags
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        // Blockquote markers
        s = s.replacingOccurrences(of: #"^>\s?"#, with: "", options: .regularExpression)
        // List markers
        s = s.replacingOccurrences(of: #"^[\-\*\+]\s"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^\d+\.\s"#, with: "", options: .regularExpression)
        // Task checkboxes
        s = s.replacingOccurrences(of: #"\[[ x]\]\s?"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Row View (selection highlight)

private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private class QuickSwitcherRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        if selectionHighlightStyle != .none {
            let selectionColor = NSColor.controlAccentColor.withAlphaComponent(0.15)
            selectionColor.setFill()
            let rect = NSInsetRect(bounds, 4, 1)
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        }
    }
}
