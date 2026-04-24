import SwiftUI
import AppKit
import ClearlyCore

/// Four-step font/icon scaling for sidebar rows. Backs the Preferences
/// "Sidebar Size" picker; stored as a raw string in `@AppStorage("sidebarSize")`.
/// Range stays tight (11/12/13/14pt font) because SwiftUI's `.listStyle(.sidebar)`
/// row chrome stops scaling cleanly above ~14pt — and rows have a hardcoded
/// minimum height that the smaller fonts fit under, so Small and Medium look
/// similar in row height while differing in font weight.
enum SidebarSize: String {
    case small, medium, large, xlarge

    static func resolve(_ raw: String) -> SidebarSize {
        SidebarSize(rawValue: raw) ?? .medium
    }

    var primaryFontSize: CGFloat {
        switch self {
        case .small: 11
        case .medium: 12
        case .large: 13
        case .xlarge: 14
        }
    }

    var secondaryFontSize: CGFloat {
        switch self {
        case .small: 8
        case .medium: 9
        case .large: 10
        case .xlarge: 11
        }
    }
}

/// Native Apple-Notes-style left sidebar. Two-column shell — folders and
/// files are both rendered as rows in this outline. Folders use
/// `DisclosureGroup` to expand/collapse; files use `doc.text` leaf rows
/// whose selection opens them in the detail column.
struct MacFolderSidebar: View {
    @Bindable var workspace: WorkspaceManager
    @Binding var selectedFileURL: URL?

    @State private var customizingFolderURL: URL?
    @State private var cachedTags: [(tag: String, count: Int)] = []
    @AppStorage("sidebarTagsExpanded") private var isTagsExpanded = true
    @AppStorage("sidebarPinnedExpanded") private var isPinnedExpanded = true
    @AppStorage("sidebarRecentsExpanded") private var isRecentsExpanded = true

    var body: some View {
        List(selection: $selectedFileURL) {
            if !workspace.pinnedFiles.isEmpty {
                pinnedSection
            }

            ForEach(workspace.locations) { location in
                locationSection(location)
            }

            if !workspace.recentFiles.isEmpty {
                recentsSection
            }

            if !cachedTags.isEmpty {
                tagsSection
            }

            if workspace.locations.isEmpty {
                ContentUnavailableView(
                    "No Vault",
                    systemImage: "folder.badge.plus",
                    description: Text("Add a folder to get started.")
                )
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.sidebar)
        .environment(\.sidebarRowSize, .small)
        .transaction { $0.disablesAnimations = true }
        .toolbar { sidebarToolbar }
        .background(SidebarSystemHighlightDisabler())
        .onAppear { refreshTags() }
        .onChange(of: workspace.vaultIndexRevision) { _, _ in refreshTags() }
    }

    // MARK: - Pinned

    private var pinnedSection: some View {
        Section {
            if isPinnedExpanded {
                ForEach(workspace.pinnedFiles, id: \.self) { url in
                    SidebarRowLabel(
                        title: url.deletingPathExtension().lastPathComponent,
                        systemImage: "doc.text",
                        iconTint: tintColor(for: url),
                        isSelected: selectedFileURL == url
                    )
                    .tag(url)
                    .listRowBackground(SelectionPill(tint: tintColor(for: url), isSelected: selectedFileURL == url))
                    .contextMenu {
                        Button("Unpin", systemImage: "pin.slash") {
                            workspace.togglePin(url)
                        }
                        Button("Open in New Tab", systemImage: "plus.rectangle.on.rectangle") {
                            workspace.openFileInNewTab(at: url)
                        }
                        Divider()
                        Button("Reveal in Finder", systemImage: "folder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                }
            }
        } header: {
            collapsibleHeader(
                title: "Pinned",
                systemImage: "pin",
                isExpanded: $isPinnedExpanded
            )
        }
    }

    // MARK: - Recents

    private var recentsSection: some View {
        Section {
            if isRecentsExpanded {
                ForEach(workspace.recentFiles, id: \.self) { url in
                    RecentRowLabel(url: url, isSelected: selectedFileURL == url)
                        .tag(url)
                        .listRowBackground(SelectionPill(tint: nil, isSelected: selectedFileURL == url))
                        .contextMenu {
                            Button("Remove from Recents") {
                                workspace.removeFromRecents(url)
                            }
                            Button("Open in New Tab", systemImage: "plus.rectangle.on.rectangle") {
                                workspace.openFileInNewTab(at: url)
                            }
                            Divider()
                            Button("Reveal in Finder", systemImage: "folder") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        }
                }
            }
        } header: {
            RecentsSectionHeader(
                isExpanded: $isRecentsExpanded,
                onClear: { workspace.clearRecents() }
            )
        }
    }

    // MARK: - Location section

    private func locationSection(_ location: BookmarkedLocation) -> some View {
        Section {
            if !workspace.isLocationCollapsed(location.id.uuidString) {
                ForEach(topLevelNodes(in: location.fileTree)) { node in
                    outlineNode(node)
                }
            }
        } header: {
            collapsibleHeader(
                title: location.name,
                systemImage: "folder",
                isExpanded: locationExpandedBinding(location)
            )
            .contextMenu {
                Button("New File", systemImage: "doc.badge.plus") {
                    createNewFile(in: location.url)
                }
                Button("New Folder…", systemImage: "folder.badge.plus") {
                    promptForNewFolder(in: location.url)
                }
                Divider()
                Button("Reveal in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([location.url])
                }
                Divider()
                Button("Remove from List", systemImage: "minus.circle", role: .destructive) {
                    workspace.removeLocationClosingOpenDocuments(location)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                workspace.handleSidebarDrop(urls: urls, into: location.url)
            }
        }
    }

    private func locationExpandedBinding(_ location: BookmarkedLocation) -> Binding<Bool> {
        Binding(
            get: { !workspace.isLocationCollapsed(location.id.uuidString) },
            set: { workspace.setLocationCollapsed(!$0, for: location.id.uuidString) }
        )
    }

    /// Recursively renders a folder/file row. Folders with children use
    /// `DisclosureGroup` bound to `WorkspaceManager.expandedFolderPaths` so
    /// expansion state persists across launches. Empty folders render flat
    /// without a chevron (matches the prior `OutlineGroup` behavior).
    ///
    /// Returns `AnyView` because a recursive function returning `some View`
    /// makes the opaque type self-referential, which Swift can't infer.
    private func outlineNode(_ node: FileNode) -> AnyView {
        if node.isDirectory, let children = node.children, !children.isEmpty {
            return AnyView(
                DisclosureGroup(isExpanded: expandedBinding(for: node.url)) {
                    ForEach(children) { child in
                        outlineNode(child)
                    }
                } label: {
                    outlineRow(node: node)
                }
            )
        } else {
            return AnyView(outlineRow(node: node))
        }
    }

    private func expandedBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { workspace.isFolderExpanded(url) },
            set: { workspace.setFolderExpanded($0, for: url) }
        )
    }

    /// Custom section header — SwiftUI's default `Label` spaces icon and text
    /// with a wide gap in sidebar sections. Swap in an `HStack` with a tight
    /// spacing so the icon sits snug next to the label. The trailing chevron
    /// rotates to indicate expanded/collapsed state and is only visible on
    /// hover so the sidebar reads as quiet chrome until the user reaches for
    /// it. The entire row is the hit target. 16pt trailing padding clears
    /// the sidebar's overlay scrollbar when present.
    private func collapsibleHeader(title: String, systemImage: String, isExpanded: Binding<Bool>) -> some View {
        CollapsibleSectionHeader(title: title, systemImage: systemImage, isExpanded: isExpanded)
    }

    // MARK: - Tags section

    private var tagsSection: some View {
        Section {
            if isTagsExpanded {
                TagFlowLayout(hSpacing: 4, vSpacing: 4) {
                    ForEach(cachedTags, id: \.tag) { entry in
                        TagChip(name: entry.tag) {
                            QuickSwitcherManager.shared.show(tagFilter: entry.tag)
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 8, trailing: 8))
                .listRowBackground(Color.clear)
            }
        } header: {
            collapsibleHeader(
                title: "Tags",
                systemImage: "tag",
                isExpanded: $isTagsExpanded
            )
        }
    }

    private func refreshTags() {
        var counts: [String: Int] = [:]
        for index in workspace.activeVaultIndexes {
            for entry in index.allTags() {
                counts[entry.tag, default: 0] += entry.count
            }
        }
        cachedTags = counts
            .map { (tag: $0.key, count: $0.value) }
            .sorted { $0.tag.localizedCaseInsensitiveCompare($1.tag) == .orderedAscending }
    }

    @ViewBuilder
    private func outlineRow(node: FileNode) -> some View {
        if node.isDirectory {
            let folderTint = workspace.folderColor(for: node.url).map(Color.init(nsColor:))
            let folderIcon = workspace.folderIcon(for: node.url) ?? "folder"
            SidebarRowLabel(
                title: node.name,
                systemImage: folderIcon,
                iconTint: folderTint,
                isSelected: false
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .listRowBackground(SelectionPill(tint: folderTint, isSelected: false))
            .contextMenu { folderContextMenu(url: node.url) }
            .popover(isPresented: popoverBinding(for: node.url), arrowEdge: .trailing) {
                FolderCustomizerView(url: node.url, workspace: workspace)
            }
            .draggable(node.url) {
                DragRowPreview(title: node.name, systemImage: folderIcon, iconTint: folderTint)
            }
            .dropDestination(for: URL.self) { urls, _ in
                workspace.handleSidebarDrop(urls: urls, into: node.url)
            }
        } else {
            let rowTint = tintColor(for: node.url)
            let isSelected = selectedFileURL == node.url
            let fileTitle = node.url.deletingPathExtension().lastPathComponent
            SidebarRowLabel(
                title: fileTitle,
                systemImage: "doc.text",
                iconTint: rowTint,
                isSelected: isSelected
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .tag(node.url)
            .listRowBackground(SelectionPill(tint: rowTint, isSelected: isSelected))
            .contextMenu { fileContextMenu(url: node.url) }
            .draggable(node.url) {
                DragRowPreview(title: fileTitle, systemImage: "doc.text", iconTint: rowTint)
            }
        }
    }

    // MARK: - Context menus

    @ViewBuilder
    private func folderContextMenu(url: URL) -> some View {
        Button("New File", systemImage: "doc.badge.plus") {
            createNewFile(in: url)
        }
        Button("New Folder…", systemImage: "folder.badge.plus") {
            promptForNewFolder(in: url)
        }
        Divider()
        Button("Customize…", systemImage: "paintpalette") {
            customizingFolderURL = url
        }
        Divider()
        Button("Reveal in Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func createNewFile(in folder: URL) {
        _ = workspace.createUntitledFileInFolder(folder)
    }

    private func promptForNewFolder(in parent: URL) {
        let alert = NSAlert()
        alert.messageText = "New Folder"
        alert.informativeText = "Enter a name for the new folder."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        textField.placeholderString = "Folder name"
        alert.accessoryView = textField
        alert.window.initialFirstResponder = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        do {
            _ = try workspace.createFolder(named: name, in: parent)
        } catch {
            let failure = NSAlert()
            failure.messageText = "Couldn't create folder"
            failure.informativeText = error.localizedDescription
            failure.alertStyle = .warning
            failure.addButton(withTitle: "OK")
            failure.runModal()
        }
    }

    @ViewBuilder
    private func fileContextMenu(url: URL) -> some View {
        Button(workspace.isPinned(url) ? "Unpin" : "Pin",
               systemImage: workspace.isPinned(url) ? "pin.slash" : "pin") {
            workspace.togglePin(url)
        }
        Button("Open in New Tab", systemImage: "plus.rectangle.on.rectangle") {
            workspace.openFileInNewTab(at: url)
        }
        Divider()
        Button("Reveal in Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                workspace.showOpenPanel()
            } label: {
                Label("Add Vault", systemImage: "folder.badge.plus")
            }
            .help("Add a vault folder")
        }
    }

    // MARK: - Derivation

    /// Top-level nodes of a vault — folders plus loose markdown files in the root.
    private func topLevelNodes(in tree: [FileNode]) -> [FileNode] {
        tree.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory // folders first
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    /// Effective tint for a row — the closest ancestor folder color (including
    /// the row itself if it's a directory with a color set), or nil.
    private func tintColor(for url: URL) -> Color? {
        workspace.effectiveFolderColor(for: url).map(Color.init(nsColor:))
    }

    private func popoverBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { customizingFolderURL == url },
            set: { if !$0 { customizingFolderURL = nil } }
        )
    }
}

// MARK: - Row label

/// Sidebar row with an icon and title. The icon tint, when set, persists
/// through selection (Apple Notes behavior — a green folder stays green
/// inside the selection pill). When no tint is set, the icon flips to the
/// accent color on selection (Finder parity). Title stays `.primary` at
/// all times; the pill itself carries the selection signal.
///
/// `isSelected` is passed explicitly rather than read from
/// `backgroundProminence` because we disable the system source-list
/// highlight (`SidebarSystemHighlightDisabler`) — and that also suppresses
/// the environment flip SwiftUI would otherwise provide.
private struct SidebarRowLabel: View {
    let title: String
    let systemImage: String
    let iconTint: Color?
    let isSelected: Bool

    @AppStorage("sidebarSize") private var sidebarSizeRaw: String = "medium"

    var body: some View {
        Label {
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(iconStyle)
        }
        .font(.system(size: SidebarSize.resolve(sidebarSizeRaw).primaryFontSize))
    }

    private var iconStyle: AnyShapeStyle {
        if let iconTint { return AnyShapeStyle(iconTint) }
        return isSelected
            ? AnyShapeStyle(.tint)
            : AnyShapeStyle(.secondary)
    }
}

/// Finder-like drag preview: icon + filename on a rounded, translucent chip.
/// Used as `.draggable(preview:)` so the cursor carries the full row during a
/// drag instead of just the SF Symbol that the default preview captures.
private struct DragRowPreview: View {
    let title: String
    let systemImage: String
    let iconTint: Color?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(iconTint ?? Color.secondary)
            Text(title)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Recents header

/// Recents section header. Mirrors `CollapsibleSectionHeader` but adds a
/// hover-revealed clear (X) button to the trailing side. The X fades in on
/// hover alongside the chevron so the sidebar stays quiet when idle. Right-
/// click on the header exposes the same "Clear Recents" action as a menu
/// fallback for discoverability.
private struct RecentsSectionHeader: View {
    @Binding var isExpanded: Bool
    let onClear: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Button { isExpanded.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text("Recents")
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onClear) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Clear Recents")
            .opacity(isHovering ? 1 : 0)

            Button { isExpanded.toggle() } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.trailing, 16)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Clear Recents", action: onClear)
        }
    }
}

// MARK: - Recent row

/// Recents row — filename followed by the parent folder name in tertiary
/// tone so the user can distinguish same-named files from different vaults.
private struct RecentRowLabel: View {
    let url: URL
    let isSelected: Bool

    @AppStorage("sidebarSize") private var sidebarSizeRaw: String = "medium"

    var body: some View {
        let size = SidebarSize.resolve(sidebarSizeRaw)
        Label {
            HStack(spacing: 6) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(url.deletingLastPathComponent().lastPathComponent)
                    .font(.system(size: size.secondaryFontSize))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } icon: {
            Image(systemName: "doc.text")
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
        }
        .font(.system(size: size.primaryFontSize))
    }
}

// MARK: - Selection pill

/// Drawn as `.listRowBackground` on every row. When the row is not selected,
/// paints `Color.clear`. When selected, paints either a subtle neutral gray
/// (default) or the folder tint at a subtle alpha.
///
/// Selection is passed explicitly because `SidebarSystemHighlightDisabler`
/// flips `NSTableView.selectionHighlightStyle` to `.none` — that also stops
/// SwiftUI from publishing `backgroundProminence == .increased` on the
/// selected row, so we can't rely on it here.
private struct SelectionPill: View {
    let tint: Color?
    let isSelected: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(fillStyle)
                .padding(.horizontal, 4)
        } else {
            Color.clear
        }
    }

    private var fillStyle: AnyShapeStyle {
        if let tint {
            let alpha = scheme == .dark ? Theme.selectionOpacityDark : Theme.selectionOpacity
            return AnyShapeStyle(tint.opacity(alpha))
        }
        // Neutral pill — matches source-list's inactive gray so default
        // rows still read as "sidebar selection" without competing with
        // the accent color.
        let alpha = scheme == .dark ? 0.18 : 0.09
        return AnyShapeStyle(Color.primary.opacity(alpha))
    }
}

// MARK: - Click modifier watcher

/// Records the modifier flags of every left-mouse-down inside the sidebar
/// region by installing a local `NSEvent` monitor. Lets the parent view
/// branch on cmd-click vs. plain-click in `.onChange(of: selectedFileURL)`
/// without losing the click's true modifier state to a delayed query of
/// `NSEvent.modifierFlags` (which can drift if the user releases the key
/// in the same runloop tick).
///
/// Filters to events whose `event.window` is the probe's window AND whose
/// `locationInWindow` falls inside the probe's bounds, so unrelated clicks
/// elsewhere in the app are ignored. Returns the event unchanged so SwiftUI
/// still updates `List` selection normally.
struct SidebarClickModifierWatcher: NSViewRepresentable {
    var onClick: (NSEvent.ModifierFlags, Date) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ProbeView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ProbeView)?.onClick = onClick
    }

    final class ProbeView: NSView {
        var onClick: ((NSEvent.ModifierFlags, Date) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, let win = self.window, event.window === win else { return event }
                let frameInWindow = self.convert(self.bounds, to: nil)
                if frameInWindow.contains(event.locationInWindow) {
                    self.onClick?(event.modifierFlags, Date())
                }
                return event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

// MARK: - System highlight suppression

/// Flips the enclosing sidebar `NSTableView.selectionHighlightStyle` to
/// `.none` so the app-drawn `SelectionPill` is the only selection indicator.
/// Required because `.listStyle(.sidebar)` ships `.sourceList` by default,
/// which paints a blue pill on top of any `.listRowBackground` we draw —
/// making per-folder color tints invisible.
private struct SidebarSystemHighlightDisabler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window,
                  let table = Self.findTableView(in: window.contentView) else { return }
            if table.selectionHighlightStyle != .none {
                table.selectionHighlightStyle = .none
            }
        }
    }

    private static func findTableView(in view: NSView?) -> NSTableView? {
        guard let view else { return nil }
        if let table = view as? NSTableView { return table }
        for sub in view.subviews {
            if let found = findTableView(in: sub) { return found }
        }
        return nil
    }
}

// MARK: - Collapsible section header

/// Section header with a hover-revealed expand/collapse chevron. Lives in
/// its own view so each header carries an isolated `@State` hover flag —
/// hovering one section can't reveal the chevron on another.
private struct CollapsibleSectionHeader: View {
    let title: String
    let systemImage: String
    @Binding var isExpanded: Bool
    @State private var isHovering = false

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.trailing, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Tag chip

/// A single tag rendered as a compact rounded-rect chip. Tighter than Apple
/// Notes (8pt/3pt padding, 5pt corner radius) to fit the sidebar's small
/// row density. Background fills are kept strictly under the selection
/// pill's opacity so chips never out-shout a selected sidebar row above.
private struct TagChip: View {
    let name: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text("#\(name)")
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
        }
        .buttonStyle(TagChipButtonStyle(isHovering: isHovering))
        .onHover { isHovering = $0 }
    }
}

private struct TagChipButtonStyle: ButtonStyle {
    let isHovering: Bool
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(fillColor(pressed: configuration.isPressed))
            )
    }

    private func fillColor(pressed: Bool) -> Color {
        let alpha: Double
        switch (scheme, pressed, isHovering) {
        case (.dark, true,  _):     alpha = 0.28
        case (.dark, false, true):  alpha = 0.20
        case (.dark, false, false): alpha = 0.14
        case (_,    true,  _):      alpha = 0.18
        case (_,    false, true):   alpha = 0.12
        default:                    alpha = 0.07
        }
        return Color.primary.opacity(alpha)
    }
}

// MARK: - Tag flow layout

/// Flexbox-style wrap layout. Walks subviews and wraps to the next line
/// when the next chip would overflow the proposed width. O(n); re-runs
/// on sidebar divider drag, which is fine for bounded chip counts.
private struct TagFlowLayout: Layout {
    var hSpacing: CGFloat
    var vSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let raw = sub.sizeThatFits(.unspecified)
            // Chips wider than the available width get clamped so they
            // stack vertically instead of bleeding off the right edge.
            let chipWidth = min(raw.width, width)
            if x + chipWidth > width && x > 0 {
                y += rowHeight + vSpacing
                x = 0
                rowHeight = 0
            }
            rowHeight = max(rowHeight, raw.height)
            x += chipWidth + hSpacing
        }
        return CGSize(width: width.isFinite ? width : 0, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let raw = sub.sizeThatFits(.unspecified)
            let chipWidth = min(raw.width, width)
            if x + chipWidth > bounds.minX + width && x > bounds.minX {
                y += rowHeight + vSpacing
                x = bounds.minX
                rowHeight = 0
            }
            sub.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: chipWidth, height: raw.height)
            )
            rowHeight = max(rowHeight, raw.height)
            x += chipWidth + hSpacing
        }
    }
}

// MARK: - Customizer popover

/// Wrapper that owns a fresh `IconPickerState` per invocation — created
/// from the current folder metadata at popover-open time, destroyed on
/// dismiss. Without this wrapper, inlining `IconPickerState(...)` inside
/// the `.popover` content closure recreates state on every re-render and
/// the picker becomes unusable.
private struct FolderCustomizerView: View {
    let url: URL
    let workspace: WorkspaceManager

    @State private var state: IconPickerState

    init(url: URL, workspace: WorkspaceManager) {
        self.url = url
        self.workspace = workspace
        _state = State(wrappedValue: IconPickerState(
            icon: workspace.folderIcons[url.path],
            color: workspace.folderColors[url.path]
        ))
    }

    var body: some View {
        IconPickerView(
            state: state,
            onSelectIcon: { icon in
                if let icon {
                    workspace.setFolderIcon(icon, for: url.path)
                } else {
                    workspace.removeFolderIcon(for: url.path)
                }
            },
            onSelectColor: { color in
                if let color {
                    workspace.setFolderColor(color, for: url.path)
                } else {
                    workspace.removeFolderColor(for: url.path)
                }
            }
        )
    }
}
