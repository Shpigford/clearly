import AppKit

// MARK: - Fuzzy Matching

struct FuzzyMatchResult {
    let score: Int
    let matchedRanges: [Range<String.Index>]
}

enum FuzzyMatcher {
    /// Sequential character matching with gap penalties and separator bonuses.
    /// Returns nil if not all query characters match.
    static func match(query: String, target: String) -> FuzzyMatchResult? {
        let queryLower = query.lowercased()
        let targetLower = target.lowercased()

        guard !queryLower.isEmpty else { return FuzzyMatchResult(score: 0, matchedRanges: []) }

        var queryIndex = queryLower.startIndex
        var targetIndex = targetLower.startIndex
        var score = 0
        var matchedRanges: [Range<String.Index>] = []
        var consecutiveMatches = 0
        var lastMatchIndex: String.Index?

        let separators: Set<Character> = ["/", ".", "_", "-", " "]

        while queryIndex < queryLower.endIndex && targetIndex < targetLower.endIndex {
            if queryLower[queryIndex] == targetLower[targetIndex] {
                // Base match score
                score += 10

                // Consecutive match bonus
                if let last = lastMatchIndex, targetLower.index(after: last) == targetIndex {
                    consecutiveMatches += 1
                    score += consecutiveMatches * 5
                } else {
                    consecutiveMatches = 0
                }

                // Separator bonus (match after separator or at start)
                if targetIndex == targetLower.startIndex {
                    score += 15
                } else {
                    let prevIndex = targetLower.index(before: targetIndex)
                    if separators.contains(targetLower[prevIndex]) {
                        score += 12
                    }
                    // CamelCase bonus
                    let origChar = target[target.index(target.startIndex, offsetBy: targetLower.distance(from: targetLower.startIndex, to: targetIndex))]
                    if origChar.isUppercase {
                        score += 8
                    }
                }

                // Record range (extend previous if consecutive)
                let origTargetIndex = target.index(target.startIndex, offsetBy: targetLower.distance(from: targetLower.startIndex, to: targetIndex))
                let nextOrigIndex = target.index(after: origTargetIndex)
                if let last = matchedRanges.last, last.upperBound == origTargetIndex {
                    matchedRanges[matchedRanges.count - 1] = last.lowerBound..<nextOrigIndex
                } else {
                    matchedRanges.append(origTargetIndex..<nextOrigIndex)
                }

                lastMatchIndex = targetIndex
                queryIndex = queryLower.index(after: queryIndex)
            } else {
                // Gap penalty
                if lastMatchIndex != nil {
                    score -= 1
                }
            }
            targetIndex = targetLower.index(after: targetIndex)
        }

        // All query characters must be matched
        guard queryIndex == queryLower.endIndex else { return nil }

        // Bonus for shorter targets (prefer exact/close matches)
        let lengthDiff = target.count - query.count
        score -= lengthDiff

        return FuzzyMatchResult(score: max(0, score), matchedRanges: matchedRanges)
    }
}

// MARK: - Quick Switcher File Item

struct QuickSwitcherItem {
    let filename: String       // e.g. "My Note"
    let relativePath: String   // e.g. "folder/My Note.md"
    let fullURL: URL
    let score: Int
    let matchedRanges: [Range<String.Index>]
    let isCreateNew: Bool

    var displayPath: String {
        let dir = (relativePath as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }
}

// MARK: - Quick Switcher Manager

@MainActor
final class QuickSwitcherManager: NSObject {
    static let shared = QuickSwitcherManager()

    private var panel: NSPanel?
    private var searchField: NSTextField?
    private var tableView: NSTableView?
    private var scrollView: NSScrollView?
    private var separator: NSBox?

    private var items: [QuickSwitcherItem] = []
    private var allFiles: [(filename: String, path: String, url: URL)] = []

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            createPanel()
        }
        refreshFileList()
        searchField?.stringValue = ""
        updateResults(query: "")
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
                return QuickSwitcherItem(
                    filename: filename,
                    relativePath: url.lastPathComponent,
                    fullURL: url,
                    score: 100,
                    matchedRanges: [],
                    isCreateNew: false
                )
            }
        } else {
            // Fuzzy match
            items = allFiles.compactMap { file in
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

            // Limit results
            if items.count > 50 { items = Array(items.prefix(50)) }

            // Add create-on-miss if no results
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
        }

        dismiss()
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

    nonisolated func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        36
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
