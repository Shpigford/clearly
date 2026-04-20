import AppKit
import ClearlyCore

// MARK: - Completion Item

struct WikiLinkCompletionItem {
    let filename: String
    let relativePath: String
    let score: Int
    let matchedRanges: [Range<String.Index>]

    var displayPath: String {
        let dir = (relativePath as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir
    }
}

// MARK: - Completion Manager

final class WikiLinkCompletionManager: NSObject {
    static let shared = WikiLinkCompletionManager()

    private var panel: NSPanel?
    private var tableView: NSTableView?
    private var scrollView: NSScrollView?

    private var items: [WikiLinkCompletionItem] = []
    private var allFiles: [(filename: String, path: String)] = []

    private(set) var isVisible = false
    private(set) var triggerLocation = 0
    private weak var activeTextView: NSTextView?

    var hasSelection: Bool {
        guard let tableView else { return false }
        return tableView.selectedRow >= 0 && tableView.selectedRow < items.count
    }

    private static let maxVisibleRows = 8
    private static let rowHeight: CGFloat = 32

    private override init() {
        super.init()
    }

    // MARK: - Lifecycle

    func show(for textView: NSTextView, triggerLocation: Int) {
        if panel == nil { createPanel() }

        activeTextView = textView
        self.triggerLocation = triggerLocation

        refreshFileList()
        updateResults(query: "")

        panel?.orderFront(nil)
        if let editorWindow = textView.window, let panel {
            editorWindow.addChildWindow(panel, ordered: .above)
        }
        isVisible = true
    }

    func dismiss() {
        guard isVisible else { return }
        if let editorWindow = activeTextView?.window, let panel {
            editorWindow.removeChildWindow(panel)
        }
        panel?.orderOut(nil)
        isVisible = false
        activeTextView = nil
        items = []
    }

    // MARK: - Panel Creation

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 0),
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

        let visualEffect = NSVisualEffectView(frame: panel.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 8
        visualEffect.layer?.masksToBounds = true
        panel.contentView?.addSubview(visualEffect)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        column.isEditable = false

        let tableView = ClickableTableView(frame: .zero)
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.action = #selector(tableClicked)
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
        visualEffect.addSubview(scrollView)
        self.scrollView = scrollView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -4),
        ])

        self.panel = panel
    }

    // MARK: - Positioning

    private func positionBelowCursor() {
        guard let textView = activeTextView, let panel else { return }

        let cursorIndex = textView.selectedRange().location
        var actualRange = NSRange()
        let screenRect = textView.firstRect(
            forCharacterRange: NSRange(location: cursorIndex, length: 0),
            actualRange: &actualRange
        )

        // Position below cursor line
        var origin = NSPoint(
            x: screenRect.origin.x,
            y: screenRect.origin.y - panel.frame.height
        )

        // Clamp to screen
        if let screen = textView.window?.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if origin.x + panel.frame.width > visible.maxX {
                origin.x = visible.maxX - panel.frame.width
            }
            if origin.x < visible.minX {
                origin.x = visible.minX
            }
            if origin.y < visible.minY {
                // Show above cursor instead
                origin.y = screenRect.maxY
            }
        }

        panel.setFrameOrigin(origin)
    }

    // MARK: - Data

    private func refreshFileList() {
        let workspace = WorkspaceManager.shared
        var files: [(filename: String, path: String)] = []
        for index in workspace.activeVaultIndexes {
            for file in index.allFiles() {
                files.append((filename: file.filename, path: file.path))
            }
        }
        allFiles = files
    }

    func updateResults(query: String) {
        if query.isEmpty {
            items = allFiles.prefix(50).map { file in
                WikiLinkCompletionItem(
                    filename: file.filename,
                    relativePath: file.path,
                    score: 0,
                    matchedRanges: []
                )
            }
        } else {
            items = allFiles.compactMap { file in
                guard let result = FuzzyMatcher.match(query: query, target: file.filename) else { return nil }
                return WikiLinkCompletionItem(
                    filename: file.filename,
                    relativePath: file.path,
                    score: result.score,
                    matchedRanges: result.matchedRanges
                )
            }
            .sorted { $0.score > $1.score }

            if items.count > 50 { items = Array(items.prefix(50)) }
        }

        tableView?.reloadData()
        if !items.isEmpty {
            tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            tableView?.scrollRowToVisible(0)
        }
        resizePanelToFit()
        positionBelowCursor()
    }

    private func resizePanelToFit() {
        guard let panel, let tableView else { return }

        let hasResults = !items.isEmpty
        scrollView?.isHidden = !hasResults

        let totalHeight: CGFloat
        if hasResults {
            tableView.tile()
            let lastVisible = min(items.count, Self.maxVisibleRows) - 1
            let tableHeight = tableView.rect(ofRow: lastVisible).maxY
            totalHeight = tableHeight + 8 // 4pt padding top + bottom
        } else {
            totalHeight = 0
        }

        var frame = panel.frame
        let delta = totalHeight - frame.height
        frame.origin.y -= delta
        frame.size.height = totalHeight
        panel.setFrame(frame, display: true, animate: false)
    }

    // MARK: - Navigation

    func moveSelectionDown() {
        guard let tableView, !items.isEmpty else { return }
        let next = min(items.count - 1, tableView.selectedRow + 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    func moveSelectionUp() {
        guard let tableView, !items.isEmpty else { return }
        let next = max(0, tableView.selectedRow - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    // MARK: - Completion

    func insertSelectedCompletion() {
        guard let textView = activeTextView,
              let tableView,
              tableView.selectedRow >= 0,
              tableView.selectedRow < items.count
        else {
            dismiss()
            return
        }

        let item = items[tableView.selectedRow]
        let cursorLocation = textView.selectedRange().location
        let replaceRange = NSRange(location: triggerLocation, length: cursorLocation - triggerLocation)
        let duplicateCount = allFiles.reduce(into: 0) { count, file in
            if file.filename.localizedCaseInsensitiveCompare(item.filename) == .orderedSame {
                count += 1
            }
        }
        let linkTarget: String
        if duplicateCount > 1 {
            let pathWithoutExtension = (item.relativePath as NSString).deletingPathExtension
            let pathDuplicateCount = allFiles.reduce(into: 0) { count, file in
                if ((file.path as NSString).deletingPathExtension).localizedCaseInsensitiveCompare(pathWithoutExtension) == .orderedSame {
                    count += 1
                }
            }
            linkTarget = pathDuplicateCount > 1 ? item.relativePath : pathWithoutExtension
        } else {
            linkTarget = item.filename
        }
        let replacement = "[[\(linkTarget)]]"

        // Dismiss first so textDidChange doesn't re-trigger
        let tv = textView
        dismiss()
        tv.insertText(replacement, replacementRange: replaceRange)
    }

    @objc private func tableClicked() {
        guard let tableView, tableView.clickedRow >= 0 else { return }
        tableView.selectRowIndexes(IndexSet(integer: tableView.clickedRow), byExtendingSelection: false)
        insertSelectedCompletion()
    }
}

// MARK: - NSTableViewDataSource

extension WikiLinkCompletionManager: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }
}

// MARK: - NSTableViewDelegate

extension WikiLinkCompletionManager: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < items.count else { return nil }
        let item = items[row]

        let cellID = NSUserInterfaceItemIdentifier("WikiLinkCompletionCell")
        let cell: WikiLinkCompletionCellView
        if let reused = tableView.makeView(withIdentifier: cellID, owner: nil) as? WikiLinkCompletionCellView {
            cell = reused
        } else {
            cell = WikiLinkCompletionCellView()
            cell.identifier = cellID
        }

        cell.configure(with: item)
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        Self.rowHeight
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        CompletionRowView()
    }
}

// MARK: - Clickable Table View

/// NSTableView subclass that forwards mouse events even when the panel isn't key.
private class ClickableTableView: NSTableView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Cell View

private class WikiLinkCompletionCellView: NSView {
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
        iconView.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Document")
        iconView.contentTintColor = .tertiaryLabelColor
        addSubview(iconView)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.maximumNumberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        addSubview(nameLabel)

        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.maximumNumberOfLines = 1
        pathLabel.lineBreakMode = .byTruncatingTail
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(pathLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            pathLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            pathLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(with item: WikiLinkCompletionItem) {
        // Use NSColor(name:) so colors stay fixed regardless of row selection state
        let textColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white
                : NSColor.black
        }
        let dimColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1, alpha: 0.45)
                : NSColor(white: 0, alpha: 0.4)
        }

        let nameString = NSMutableAttributedString(string: item.filename, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: textColor,
        ])

        for range in item.matchedRanges {
            let nsRange = NSRange(range, in: item.filename)
            nameString.addAttributes([
                .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: Theme.accentColor,
            ], range: nsRange)
        }

        nameLabel.attributedStringValue = nameString

        let displayPath = item.displayPath
        if displayPath.isEmpty {
            pathLabel.stringValue = ""
        } else {
            pathLabel.attributedStringValue = NSAttributedString(string: displayPath, attributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: dimColor,
            ])
        }
    }
}

// MARK: - Row View

private class CompletionRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        if selectionHighlightStyle != .none {
            let selectionColor = NSColor.controlAccentColor.withAlphaComponent(0.15)
            selectionColor.setFill()
            let rect = NSInsetRect(bounds, 4, 1)
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        }
    }
}
