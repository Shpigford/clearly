import Foundation
import AppKit
import CoreServices
import UniformTypeIdentifiers

/// Central state manager for file navigation: locations, recents, and current file.
@Observable
final class WorkspaceManager {
    static let shared = WorkspaceManager()

    // MARK: - Locations

    var locations: [BookmarkedLocation] = []

    // MARK: - Recents

    var recentFiles: [URL] = []
    private static let maxRecents = 5

    // MARK: - Current File

    var currentFileURL: URL?
    var currentFileText: String = ""
    var isDirty: Bool = false

    // MARK: - Sidebar

    var isSidebarVisible: Bool = false

    // MARK: - Private

    private var fsStreams: [UUID: FSEventStreamRef] = [:]
    private var autoSaveWork: DispatchWorkItem?
    private var lastSavedText: String = ""
    private var accessedURLs: Set<URL> = []

    // MARK: - UserDefaults Keys

    private static let locationBookmarksKey = "locationBookmarks"
    private static let recentBookmarksKey = "recentBookmarks"
    private static let lastOpenFileKey = "lastOpenFileURL"
    private static let sidebarVisibleKey = "sidebarVisible"

    // MARK: - Init

    init() {
        isSidebarVisible = UserDefaults.standard.bool(forKey: Self.sidebarVisibleKey)
        restoreLocations()
        restoreRecents()
        restoreLastFile()
    }

    deinit {
        autoSaveWork?.cancel()
        stopAllFSStreams()
        for url in accessedURLs {
            url.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Sidebar Toggle

    func toggleSidebar() {
        isSidebarVisible.toggle()
        UserDefaults.standard.set(isSidebarVisible, forKey: Self.sidebarVisibleKey)
    }

    // MARK: - Open File

    @discardableResult
    func openFile(at url: URL) -> Bool {
        // Auto-save previous file
        guard saveCurrentFileIfDirty() else { return false }

        // Load new file
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            DiagnosticLog.log("Failed to read file: \(url.lastPathComponent)")
            return false
        }

        currentFileURL = url
        currentFileText = text
        lastSavedText = text
        isDirty = false

        addToRecents(url)

        // Persist last open file
        if let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmarkData, forKey: Self.lastOpenFileKey)
        }

        DiagnosticLog.log("Opened file: \(url.lastPathComponent)")
        presentMainWindow()
        return true
    }

    // MARK: - Text Changes

    /// Called when the editor binding updates currentFileText.
    /// Does NOT set currentFileText — the binding already did that.
    func contentDidChange() {
        isDirty = currentFileText != lastSavedText
        if isDirty { scheduleAutoSave() }
    }

    /// Called when FileWatcher detects an external modification.
    func externalFileDidChange(_ newText: String) {
        currentFileText = newText
        lastSavedText = newText
        isDirty = false
    }

    // MARK: - Save

    @discardableResult
    func saveCurrentFile() -> Bool {
        guard let url = currentFileURL else { return true }
        guard isDirty else { return true }
        do {
            try currentFileText.write(to: url, atomically: true, encoding: .utf8)
            lastSavedText = currentFileText
            isDirty = false
            return true
        } catch {
            DiagnosticLog.log("Failed to save file: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func saveCurrentFileIfDirty() -> Bool {
        autoSaveWork?.cancel()
        autoSaveWork = nil
        if isDirty { return saveCurrentFile() }
        return true
    }

    private func scheduleAutoSave() {
        autoSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                self?.saveCurrentFile()
            }
        }
        autoSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    // MARK: - Locations

    func addLocation(url: URL) {
        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            DiagnosticLog.log("Failed to create bookmark for location: \(url.path)")
            return
        }

        guard url.startAccessingSecurityScopedResource() else {
            DiagnosticLog.log("Failed to access location: \(url.path)")
            return
        }
        accessedURLs.insert(url)

        let tree = FileNode.buildTree(at: url)
        let location = BookmarkedLocation(
            url: url,
            bookmarkData: bookmarkData,
            fileTree: tree,
            isAccessible: true
        )
        locations.append(location)
        persistLocations()
        startFSStream(for: location)

        DiagnosticLog.log("Added location: \(url.lastPathComponent)")
    }

    func removeLocation(_ location: BookmarkedLocation) {
        stopFSStream(for: location.id)
        if accessedURLs.contains(location.url) {
            location.url.stopAccessingSecurityScopedResource()
            accessedURLs.remove(location.url)
        }
        locations.removeAll { $0.id == location.id }
        persistLocations()
    }

    func refreshTree(for locationID: UUID) {
        guard let index = locations.firstIndex(where: { $0.id == locationID }) else { return }
        locations[index].fileTree = FileNode.buildTree(at: locations[index].url)
    }

    // MARK: - Recents

    func addToRecents(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        recentFiles.insert(url, at: 0)
        if recentFiles.count > Self.maxRecents {
            recentFiles = Array(recentFiles.prefix(Self.maxRecents))
        }
        persistRecents()
    }

    // MARK: - File Operations

    func createFile(named name: String, in folderURL: URL) -> URL? {
        let fileName = name.hasSuffix(".md") ? name : "\(name).md"
        let fileURL = folderURL.appendingPathComponent(fileName)

        // Don't overwrite existing files
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            DiagnosticLog.log("File already exists: \(fileName)")
            return nil
        }

        do {
            try "".write(to: fileURL, atomically: true, encoding: .utf8)
            DiagnosticLog.log("Created file: \(fileName)")
            return fileURL
        } catch {
            DiagnosticLog.log("Failed to create file: \(error.localizedDescription)")
            return nil
        }
    }

    func createFolder(named name: String, in parentURL: URL) -> URL? {
        let folderURL = parentURL.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
            DiagnosticLog.log("Created folder: \(name)")
            return folderURL
        } catch {
            DiagnosticLog.log("Failed to create folder: \(error.localizedDescription)")
            return nil
        }
    }

    func renameItem(at url: URL, to newName: String) -> URL? {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: url, to: newURL)
            // If the renamed file was open, update the reference
            if currentFileURL == url {
                currentFileURL = newURL
            }
            DiagnosticLog.log("Renamed: \(url.lastPathComponent) → \(newName)")
            return newURL
        } catch {
            DiagnosticLog.log("Failed to rename: \(error.localizedDescription)")
            return nil
        }
    }

    func deleteItem(at url: URL) -> Bool {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            if currentFileURL == url {
                currentFileURL = nil
                currentFileText = ""
                lastSavedText = ""
                isDirty = false
            }
            DiagnosticLog.log("Trashed: \(url.lastPathComponent)")
            return true
        } catch {
            DiagnosticLog.log("Failed to trash: \(error.localizedDescription)")
            return false
        }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Open Panel (supports both files and folders)

    func showNewFilePanel(defaultFileName: String = "Untitled.md") {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.daringFireballMarkdown]
        panel.nameFieldStringValue = defaultFileName
        panel.prompt = "Create"
        panel.message = "Create a new markdown file"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
            _ = openFile(at: url)
        } catch {
            DiagnosticLog.log("Failed to create new file: \(error.localizedDescription)")
        }
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.daringFireballMarkdown, .plainText, .text]
        panel.message = "Choose a file to open or a folder to add to your sidebar"
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        if isDir.boolValue {
            // Don't add duplicate locations
            guard !locations.contains(where: { $0.url == url }) else { return }
            addLocation(url: url)
            if !isSidebarVisible { toggleSidebar() }
            presentMainWindow()
        } else {
            _ = openFile(at: url)
        }
    }

    // MARK: - Persistence: Locations

    private func persistLocations() {
        let stored = locations.map { StoredBookmark(id: $0.id, bookmarkData: $0.bookmarkData) }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.locationBookmarksKey)
        }
    }

    private func restoreLocations() {
        guard let data = UserDefaults.standard.data(forKey: Self.locationBookmarksKey),
              let stored = try? JSONDecoder().decode([StoredBookmark].self, from: data) else { return }

        for bookmark in stored {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark.bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }

            var bookmarkData = bookmark.bookmarkData
            if isStale {
                if let refreshed = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    bookmarkData = refreshed
                }
            }

            guard url.startAccessingSecurityScopedResource() else { continue }
            accessedURLs.insert(url)

            let tree = FileNode.buildTree(at: url)
            let location = BookmarkedLocation(
                id: bookmark.id,
                url: url,
                bookmarkData: bookmarkData,
                fileTree: tree,
                isAccessible: true
            )
            locations.append(location)
            startFSStream(for: location)
        }

        if !stored.isEmpty {
            persistLocations() // Re-persist in case any bookmarks were refreshed
        }
    }

    // MARK: - Persistence: Recents

    private func persistRecents() {
        let bookmarks: [Data] = recentFiles.compactMap { url in
            try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        UserDefaults.standard.set(bookmarks, forKey: Self.recentBookmarksKey)
    }

    private func restoreRecents() {
        guard let bookmarks = UserDefaults.standard.array(forKey: Self.recentBookmarksKey) as? [Data] else { return }

        var urls: [URL] = []
        var shouldPersist = false
        for data in bookmarks {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if isStale {
                    shouldPersist = true
                }
                if !hasActiveAccess(to: url), url.startAccessingSecurityScopedResource() {
                    accessedURLs.insert(url)
                }
                urls.append(url)
            } else {
                shouldPersist = true
            }
        }
        recentFiles = urls
        if shouldPersist || urls.count != bookmarks.count {
            persistRecents()
        }
    }

    // MARK: - Persistence: Last Open File

    private func restoreLastFile() {
        guard let data = UserDefaults.standard.data(forKey: Self.lastOpenFileKey) else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }

        // Need to start access for files inside bookmarked locations OR standalone files
        let needsAccess = !hasActiveAccess(to: url)
        if needsAccess {
            if url.startAccessingSecurityScopedResource() {
                accessedURLs.insert(url)
            } else {
                return
            }
        }

        if isStale {
            if let refreshed = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(refreshed, forKey: Self.lastOpenFileKey)
            }
        }

        // Only open if file still exists
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        openFile(at: url)
    }

    // MARK: - FSEventStream

    private func startFSStream(for location: BookmarkedLocation) {
        let locationID = location.id
        let path = location.url.path as CFString

        var context = FSEventStreamContext()
        let info = Unmanaged.passRetained(FSStreamInfo(manager: self, locationID: locationID))
        context.info = info.toOpaque()
        context.release = { info in
            guard let info else { return }
            Unmanaged<FSStreamInfo>.fromOpaque(info).release()
        }

        guard let stream = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let streamInfo = Unmanaged<FSStreamInfo>.fromOpaque(info).takeUnretainedValue()
                DispatchQueue.main.async { [weak manager = streamInfo.manager] in
                    manager?.refreshTree(for: streamInfo.locationID)
                }
            },
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return }

        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
        fsStreams[locationID] = stream
    }

    private func stopFSStream(for locationID: UUID) {
        guard let stream = fsStreams.removeValue(forKey: locationID) else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func stopAllFSStreams() {
        let ids = Array(fsStreams.keys)
        for id in ids {
            stopFSStream(for: id)
        }
    }

    private func presentMainWindow() {
        Task { @MainActor in
            WindowRouter.shared.showMainWindow()
        }
    }

    private func hasActiveAccess(to url: URL) -> Bool {
        let targetPath = url.standardizedFileURL.path
        return accessedURLs.contains { accessedURL in
            let scopePath = accessedURL.standardizedFileURL.path
            return targetPath == scopePath || targetPath.hasPrefix(scopePath + "/")
        }
    }
}

// MARK: - FSEventStream Helper

private final class FSStreamInfo {
    weak var manager: WorkspaceManager?
    let locationID: UUID

    init(manager: WorkspaceManager, locationID: UUID) {
        self.manager = manager
        self.locationID = locationID
    }
}
