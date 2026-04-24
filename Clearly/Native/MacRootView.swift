import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ClearlyCore

/// Root view for the native macOS shell — two-column `NavigationSplitView`:
/// sidebar holds the folder-and-file outline, detail holds the editor +
/// preview + toolbar. Clicking a file in the sidebar opens it in the
/// detail; clicking a folder just expands/collapses it.
struct MacRootView: View {
    @Bindable var workspace: WorkspaceManager
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedFileURL: URL? = nil
    @State private var positionSyncID: String = UUID().uuidString
    @State private var showFormatPopover = false
    @State private var lastSidebarClickModifiers: NSEvent.ModifierFlags = []
    @State private var lastSidebarClickTime: Date? = nil
    @StateObject private var findState = FindState()
    @StateObject private var outlineState = OutlineState()
    @StateObject private var backlinksState = BacklinksState()
    @StateObject private var jumpToLineState = JumpToLineState()

    var body: some View {
        if workspace.isFirstRun && workspace.locations.isEmpty && workspace.activeDocumentID == nil {
            WelcomeView(workspace: workspace)
        } else {
            splitView
                .background(AppKitDropCatcher { urls in
                    DiagnosticLog.log("AppKitDropCatcher handling \(urls.count) URL(s)")
                    NotificationCenter.default.post(
                        name: ClearlyTextView.insertDroppedImagesNotification,
                        object: nil, userInfo: ["urls": urls]
                    )
                })
                .onDrop(of: ["public.file-url"], delegate: ImageFileDropDelegate())
        }
    }

    @ViewBuilder
    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            MacFolderSidebar(
                workspace: workspace,
                selectedFileURL: $selectedFileURL
            )
            .background(SidebarClickModifierWatcher { mods, time in
                lastSidebarClickModifiers = mods
                lastSidebarClickTime = time
            })
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            VStack(spacing: 0) {
                MacTabBar(workspace: workspace)
                MacDetailColumn(
                    workspace: workspace,
                    findState: findState,
                    outlineState: outlineState,
                    backlinksState: backlinksState,
                    jumpToLineState: jumpToLineState,
                    positionSyncID: $positionSyncID,
                    showFormatPopover: $showFormatPopover
                )
            }
            .toolbar {
                MacDetailToolbar(
                    workspace: workspace,
                    findState: findState,
                    outlineState: outlineState,
                    backlinksState: backlinksState,
                    showFormatPopover: $showFormatPopover
                )
            }
        }
        .navigationTitle(windowTitle)
        .navigationDocument(workspace.currentFileURL ?? URL(fileURLWithPath: "/"))
        .onChange(of: selectedFileURL) { _, newURL in
            guard let url = newURL else { return }
            guard workspace.currentFileURL != url else { return }
            let isCmdClick: Bool = {
                guard let t = lastSidebarClickTime, Date().timeIntervalSince(t) < 0.25 else { return false }
                return lastSidebarClickModifiers.contains(.command)
            }()
            lastSidebarClickModifiers = []
            lastSidebarClickTime = nil
            if isCmdClick {
                workspace.openFileInNewTab(at: url)
            } else {
                workspace.openFile(at: url)
            }
        }
        .onChange(of: workspace.currentFileURL) { _, newURL in
            if selectedFileURL != newURL {
                selectedFileURL = newURL
            }
        }
    }

    private var windowTitle: String {
        guard let docID = workspace.activeDocumentID,
              let doc = workspace.openDocuments.first(where: { $0.id == docID }) else {
            return "Clearly"
        }
        return workspace.isDirty ? "\u{2022} \(doc.displayName)" : doc.displayName
    }
}

/// Routes Finder file drops anywhere in the main window to the currently
/// focused `ClearlyTextView`. SwiftUI's `.onDrop(of:delegate:)` is the
/// canonical macOS pattern; `.dropDestination(for:URL.self)` and `.onDrop`
/// on NSViewRepresentable both proved unreliable under `NavigationSplitView`.
struct ImageFileDropDelegate: DropDelegate {

    func validateDrop(info: DropInfo) -> Bool {
        let ok = info.hasItemsConforming(to: ["public.file-url"])
        DiagnosticLog.log("DROP validateDrop ok=\(ok) loc=\(info.location)")
        return ok
    }

    func dropEntered(info: DropInfo) {
        DiagnosticLog.log("DROP dropEntered loc=\(info.location)")
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DiagnosticLog.log("DROP dropUpdated loc=\(info.location)")
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        DiagnosticLog.log("DROP dropExited loc=\(info.location)")
    }

    func performDrop(info: DropInfo) -> Bool {
        DiagnosticLog.log("DROP performDrop ENTERED loc=\(info.location)")
        let providers = info.itemProviders(for: ["public.file-url"])
        DiagnosticLog.log("DROP performDrop providers=\(providers.count)")
        guard !providers.isEmpty else { return false }

        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await Self.loadFileURL(from: provider) { urls.append(url) }
            }
            DiagnosticLog.log("DROP resolved \(urls.count) URLs: \(urls.map(\.lastPathComponent).joined(separator: ","))")
            guard !urls.isEmpty else { return }
            NotificationCenter.default.post(
                name: ClearlyTextView.insertDroppedImagesNotification,
                object: nil, userInfo: ["urls": urls]
            )
        }
        return true
    }

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { cont in
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    cont.resume(returning: url)
                } else if let url = item as? URL {
                    cont.resume(returning: url)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}

/// Fallback AppKit drop catcher placed as a SwiftUI `.background`. Registers
/// directly with `NSView`'s drag machinery so we get definitive diagnostics
/// even when SwiftUI's drop chain misbehaves inside a `NavigationSplitView`.
struct AppKitDropCatcher: NSViewRepresentable {
    let onDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> DropCatcherView {
        let v = DropCatcherView()
        v.onDrop = onDrop
        v.registerForDraggedTypes([.fileURL, .tiff, .png, .URL])
        DiagnosticLog.log("AppKitDropCatcher makeNSView registered=\(v.registeredDraggedTypes.map(\.rawValue).joined(separator: ","))")
        return v
    }

    func updateNSView(_ nsView: DropCatcherView, context: Context) {
        nsView.onDrop = onDrop
    }

    final class DropCatcherView: NSView {
        var onDrop: (([URL]) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Don't intercept mouse events — only drag events.
            return nil
        }

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            DiagnosticLog.log("DropCatcherView draggingEntered")
            return .copy
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            return .copy
        }

        override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            DiagnosticLog.log("DropCatcherView prepareForDragOperation")
            return true
        }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            DiagnosticLog.log("DropCatcherView performDragOperation")
            let pb = sender.draggingPasteboard
            guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingFileURLsOnly: true
            ]) as? [URL], !urls.isEmpty else {
                DiagnosticLog.log("DropCatcherView no file URLs on pasteboard")
                return false
            }
            onDrop?(urls)
            return true
        }
    }
}
