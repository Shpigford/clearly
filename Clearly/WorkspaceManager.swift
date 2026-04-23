import Foundation
import ClearlyCore
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

    // MARK: - Pinned Files

    var pinnedFiles: [URL] = []

    // MARK: - Current File (active document buffer)

    var currentFileURL: URL?
    var currentFileText: String = ""
    var isDirty: Bool = false
    var currentViewMode: ViewMode = .edit
    var currentConflictOutcome: ConflictResolver.Outcome?

    // MARK: - Open Documents

    var openDocuments: [OpenDocument] = []
    var activeDocumentID: UUID?
    var hoveredTabID: UUID?
    private var nextUntitledNumber: Int = 1

    // MARK: - Sidebar

    var isSidebarVisible: Bool = false
    var showHiddenFiles: Bool = false

    // MARK: - Private

    private var fsStreams: [UUID: FSEventStreamRef] = [:]
    @ObservationIgnored private var vaultIndexes: [UUID: VaultIndex] = [:]
    @ObservationIgnored private var refreshWork: [UUID: DispatchWorkItem] = [:]
    @ObservationIgnored private var treeBuildGeneration: [UUID: Int] = [:]
    private var autoSaveWork: DispatchWorkItem?
    private var lastSavedText: String = ""
    private var accessedURLs: Set<URL> = []

    var activeVaultIndexes: [VaultIndex] { Array(vaultIndexes.values) }
    private(set) var vaultIndexRevision: Int = 0
    private(set) var treeRevision: Int = 0

    // MARK: - UserDefaults Keys

    private static let locationBookmarksKey = "locationBookmarks"
    private static let recentBookmarksKey = "recentBookmarks"
    private static let lastOpenFileKey = "lastOpenFileURL"
    private static let sidebarVisibleKey = "sidebarVisible"
    private static let launchBehaviorKey = "launchBehavior"
    private static let folderIconsKey = "folderIcons"
    private static let folderColorsKey = "folderColors"
    private static let expandedFolderPathsKey = "expandedFolderPaths"
    private static let collapsedLocationIDsKey = "collapsedLocationIDs"
    private static let showHiddenFilesKey = "showHiddenFiles"
    private static let hasEverAddedLocationKey = "hasEverAddedLocation"
    private static let hasDeliveredGettingStartedKey = "hasDeliveredGettingStarted"
    private static let pinnedBookmarksKey = "pinnedBookmarks"
    private static let wikiLinkPattern = try! NSRegularExpression(pattern: "\\[\\[[^\\]]*\\]\\]")

    /// Custom folder icons keyed by folder path (URL.path → SF Symbol name).
    var folderIcons: [String: String] = [:]
    /// Custom folder colors keyed by folder path (URL.path → color name).
    var folderColors: [String: String] = [:]
    /// Expanded folder paths (URL.path). Presence = expanded; absence = collapsed.
    var expandedFolderPaths: Set<String> = []
    /// Collapsed vault section IDs (BookmarkedLocation.id.uuidString). Presence = collapsed; absence = expanded (default).
    var collapsedLocationIDs: Set<String> = []

    /// True when the user has never added a location (first-run state).
    var isFirstRun: Bool {
        !UserDefaults.standard.bool(forKey: Self.hasEverAddedLocationKey)
    }

    private enum DirtyDocumentDisposition {
        case save
        case discard
        case cancel
    }

    // MARK: - Init

    init() {
        isSidebarVisible = UserDefaults.standard.bool(forKey: Self.sidebarVisibleKey)
        showHiddenFiles = UserDefaults.standard.bool(forKey: Self.showHiddenFilesKey)
        folderIcons = UserDefaults.standard.dictionary(forKey: Self.folderIconsKey) as? [String: String] ?? [:]
        folderColors = UserDefaults.standard.dictionary(forKey: Self.folderColorsKey) as? [String: String] ?? [:]
        expandedFolderPaths = Set(UserDefaults.standard.stringArray(forKey: Self.expandedFolderPathsKey) ?? [])
        collapsedLocationIDs = Set(UserDefaults.standard.stringArray(forKey: Self.collapsedLocationIDsKey) ?? [])
        restoreLocations()
        restoreRecents()
        restorePinnedFiles()

        // Backfill for users upgrading from before the welcome view
        if !locations.isEmpty && !UserDefaults.standard.bool(forKey: Self.hasEverAddedLocationKey) {
            UserDefaults.standard.set(true, forKey: Self.hasEverAddedLocationKey)
        }

        let launchBehavior = UserDefaults.standard.string(forKey: Self.launchBehaviorKey) ?? "lastFile"
        if launchBehavior == "newDocument" {
            createUntitledDocument()
        } else {
            restoreLastFile()
        }
    }

    deinit {
        autoSaveWork?.cancel()
        refreshWork.values.forEach { $0.cancel() }
        for index in vaultIndexes.values { index.close() }
        vaultIndexes.removeAll()
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

    func toggleShowHiddenFiles() {
        showHiddenFiles.toggle()
        UserDefaults.standard.set(showHiddenFiles, forKey: Self.showHiddenFilesKey)
        for location in locations {
            refreshWork[location.id]?.cancel()
            refreshWork.removeValue(forKey: location.id)
            loadTree(for: location.id, at: location.url)
        }
        reindexAllVaults()
    }

    // MARK: - Open Documents

    @discardableResult
    func createUntitledDocument() -> Bool {
        guard saveFileBacked() else { return false }
        snapshotActiveDocument()
        let doc = OpenDocument(
            id: UUID(),
            fileURL: nil,
            text: "",
            lastSavedText: "",
            untitledNumber: nextUntitledNumber
        )
        nextUntitledNumber += 1
        openDocuments.append(doc)
        activateDocument(doc)
        DiagnosticLog.log("Created untitled document: \(doc.displayName)")
        presentMainWindow()
        return true
    }

    /// Create an empty `untitled.md` (or `untitled-2.md`, …) inside `folder`
    /// and open it in the active tab. Returns the new file URL on success.
    /// The file auto-renames from its first heading/line on the next save.
    /// If opening the file fails (e.g. the user cancels the save-dirty-doc
    /// prompt), the just-created empty file is deleted so the vault doesn't
    /// accumulate ghost notes.
    @discardableResult
    func createUntitledFileInFolder(_ folder: URL) -> URL? {
        let url = UntitledRename.nextUntitledURL(in: folder)
        do {
            try CoordinatedFileIO.write(Data(), to: url)
        } catch {
            DiagnosticLog.log("Failed to create untitled file in \(folder.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
        revealFolderInSidebar(folder)
        guard openFile(at: url) else {
            try? CoordinatedFileIO.delete(at: url)
            return nil
        }
        return url
    }

    /// Create a new folder inside `parent`. Name is kebab-sanitized for
    /// filesystem consistency. Throws if the name is empty or a folder with
    /// that name already exists. Returns the created folder URL.
    @discardableResult
    func createFolder(named name: String, in parent: URL) throws -> URL {
        let cleanName = UntitledRename.sanitizeFilename(name)
        guard !cleanName.isEmpty else {
            throw NSError(domain: "ClearlyWorkspace", code: 1, userInfo: [NSLocalizedDescriptionKey: "Folder name is empty."])
        }
        let folderURL = parent.appendingPathComponent(cleanName)
        if FileManager.default.fileExists(atPath: folderURL.path) {
            throw NSError(domain: "ClearlyWorkspace", code: 2, userInfo: [NSLocalizedDescriptionKey: "A folder with that name already exists."])
        }
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        revealFolderInSidebar(parent)
        return folderURL
    }

    /// Makes sure `folder` is visible in the sidebar: un-collapses its owning
    /// location if `folder` is the vault root, expands the disclosure group
    /// otherwise, and kicks a debounced tree refresh so the new child shows.
    private func revealFolderInSidebar(_ folder: URL) {
        let target = folder.standardizedFileURL.path
        var matchedLocationID: UUID?
        for loc in locations {
            let root = loc.url.standardizedFileURL.path
            guard target == root || target.hasPrefix(root + "/") else { continue }
            matchedLocationID = loc.id
            if target == root {
                setLocationCollapsed(false, for: loc.id.uuidString)
            }
            break
        }
        if matchedLocationID != nil {
            setFolderExpanded(true, for: folder)
            if let id = matchedLocationID {
                refreshTree(for: id)
            }
        }
    }

    @discardableResult
    func createDocumentWithContent(_ content: String) -> Bool {
        guard saveFileBacked() else { return false }
        snapshotActiveDocument()
        let doc = OpenDocument(
            id: UUID(),
            fileURL: nil,
            text: content,
            lastSavedText: "",
            untitledNumber: nextUntitledNumber
        )
        nextUntitledNumber += 1
        openDocuments.append(doc)
        activateDocument(doc)
        DiagnosticLog.log("Created document with content: \(doc.displayName)")
        presentMainWindow()
        return true
    }

    @discardableResult
    func switchToDocument(_ id: UUID) -> Bool {
        guard id != activeDocumentID else { return true }
        guard openDocuments.contains(where: { $0.id == id }) else { return false }
        guard saveFileBacked() else { return false }
        snapshotActiveDocument()
        activeDocumentID = id
        restoreActiveDocument()
        return true
    }

    @discardableResult
    func closeDocument(_ id: UUID) -> Bool {
        guard openDocuments.contains(where: { $0.id == id }) else { return true }
        let wasCurrent = (id == activeDocumentID)

        if wasCurrent {
            snapshotActiveDocument()
            guard saveFileBacked() else { return false }
        }

        guard let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return true }
        let doc = openDocuments[idx]
        if doc.isDirty {
            switch promptToSaveChanges(for: doc) {
            case .save:
                guard saveDocument(at: idx, treatCancelAsFailure: true) else { return false }
            case .discard:
                break
            case .cancel:
                return false
            }
        }

        removeDocument(id)
        return true
    }

    func selectNextTab() {
        guard let id = activeDocumentID,
              let idx = openDocuments.firstIndex(where: { $0.id == id }),
              openDocuments.count > 1 else { return }
        let next = (idx + 1) % openDocuments.count
        switchToDocument(openDocuments[next].id)
    }

    func selectPreviousTab() {
        guard let id = activeDocumentID,
              let idx = openDocuments.firstIndex(where: { $0.id == id }),
              openDocuments.count > 1 else { return }
        let prev = (idx - 1 + openDocuments.count) % openDocuments.count
        switchToDocument(openDocuments[prev].id)
    }

    @discardableResult
    func prepareForAppTermination() -> Bool {
        snapshotActiveDocument()
        guard saveFileBacked() else { return false }

        for docID in openDocuments.map(\.id) {
            guard let idx = openDocuments.firstIndex(where: { $0.id == docID }) else { continue }
            let doc = openDocuments[idx]
            guard doc.isDirty else { continue }

            switch promptToSaveChanges(for: doc) {
            case .save:
                guard saveDocument(at: idx, treatCancelAsFailure: true) else { return false }
            case .discard:
                break
            case .cancel:
                return false
            }
        }

        return true
    }

    @discardableResult
    func prepareForWindowClose() -> Bool {
        snapshotActiveDocument()
        guard saveFileBacked() else { return false }

        let docIDs = openDocuments.map(\.id)
        for docID in docIDs {
            guard let idx = openDocuments.firstIndex(where: { $0.id == docID }) else { continue }
            let doc = openDocuments[idx]
            guard doc.isDirty else { continue }

            switch promptToSaveChanges(for: doc) {
            case .save:
                guard saveDocument(at: idx, treatCancelAsFailure: true) else { return false }
            case .discard:
                discardChanges(to: docID)
            case .cancel:
                return false
            }
        }

        return true
    }

    // MARK: - Open File

    /// Opens a file by replacing the active tab's content (no new tab created).
    @discardableResult
    func openFile(at url: URL) -> Bool {
        // If already open in a tab, just switch to it
        if let existing = openDocuments.first(where: { $0.fileURL == url }) {
            return switchToDocument(existing.id)
        }

        // Save current file-backed document before switching
        guard saveFileBacked() else { return false }

        // Load new file
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            DiagnosticLog.log("Failed to read file: \(url.lastPathComponent)")
            return false
        }

        if let idx = activeDocumentIndex {
            // If the active document is dirty and untitled, prompt before replacing
            snapshotActiveDocument()
            let activeDoc = openDocuments[idx]
            if activeDoc.isDirty && activeDoc.isUntitled {
                switch promptToSaveChanges(for: activeDoc) {
                case .save:
                    guard saveDocument(at: idx, treatCancelAsFailure: true) else { return false }
                case .discard:
                    break
                case .cancel:
                    return false
                }
            }
            // Replace the active tab's content in place
            openDocuments[idx].fileURL = url
            openDocuments[idx].text = text
            openDocuments[idx].lastSavedText = text
            openDocuments[idx].untitledNumber = nil
            openDocuments[idx].conflictOutcome = nil
            currentFileURL = url
            currentFileText = text
            lastSavedText = text
            isDirty = false
            currentConflictOutcome = nil
            refreshConflictOutcomeForActiveDocument()
        } else {
            // No active document — create one
            let doc = OpenDocument(
                id: UUID(),
                fileURL: url,
                text: text,
                lastSavedText: text,
                untitledNumber: nil
            )
            openDocuments.append(doc)
            activateDocument(doc)
        }

        addToRecents(url)
        persistLastOpenFile(url)

        DiagnosticLog.log("Opened file: \(url.lastPathComponent)")
        presentMainWindow()
        return true
    }

    /// Opens a file in a new tab (Cmd+click or Cmd+T then navigate).
    @discardableResult
    func openFileInNewTab(at url: URL) -> Bool {
        // If already open in a tab, just switch to it
        if let existing = openDocuments.first(where: { $0.fileURL == url }) {
            return switchToDocument(existing.id)
        }

        guard saveFileBacked() else { return false }

        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            DiagnosticLog.log("Failed to read file: \(url.lastPathComponent)")
            return false
        }

        snapshotActiveDocument()

        let doc = OpenDocument(
            id: UUID(),
            fileURL: url,
            text: text,
            lastSavedText: text,
            untitledNumber: nil
        )
        openDocuments.append(doc)
        activateDocument(doc)

        addToRecents(url)
        persistLastOpenFile(url)

        DiagnosticLog.log("Opened file in new tab: \(url.lastPathComponent)")
        presentMainWindow()
        return true
    }

    // MARK: - Text Changes

    /// Called when the editor binding updates currentFileText.
    /// Does NOT set currentFileText — the binding already did that.
    func contentDidChange() {
        isDirty = currentFileText != lastSavedText
        // Sync text to the open document
        if let idx = activeDocumentIndex {
            openDocuments[idx].text = currentFileText
        }
        // Only auto-save file-backed documents
        if isDirty, currentFileURL != nil {
            scheduleAutoSave()
        }
    }

    /// Called when FileWatcher detects an external modification.
    func externalFileDidChange(_ newText: String) {
        currentFileText = newText
        lastSavedText = newText
        isDirty = false
        if let idx = activeDocumentIndex {
            openDocuments[idx].text = newText
            openDocuments[idx].lastSavedText = newText
        }
        refreshConflictOutcomeForActiveDocument()
    }

    /// Clears the active document's resolved-conflict record after the user has
    /// viewed the diff sheet.
    func dismissCurrentConflict() {
        currentConflictOutcome = nil
        if let idx = activeDocumentIndex {
            openDocuments[idx].conflictOutcome = nil
        }
    }

    private func refreshConflictOutcomeForActiveDocument() {
        guard let url = currentFileURL else {
            currentConflictOutcome = nil
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result: Result<ConflictResolver.Outcome?, Error>
            do {
                result = .success(try ConflictResolver.resolveIfNeeded(at: url, presenter: nil))
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async {
                guard let self, self.currentFileURL == url else { return }
                switch result {
                case .success(let outcome):
                    guard let outcome else { return }
                    self.currentConflictOutcome = outcome
                    if let idx = self.activeDocumentIndex,
                       self.openDocuments[idx].fileURL == url {
                        self.openDocuments[idx].conflictOutcome = outcome
                    }
                case .failure(let error):
                    DiagnosticLog.log("ConflictResolver failed for \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
    }

    @discardableResult
    func insertWikiLink(in fileURL: URL, matching searchTerm: String, linkTarget: String, atLine lineNumber: Int) -> Bool {
        guard !searchTerm.isEmpty, !linkTarget.isEmpty, lineNumber > 0 else { return false }

        let openDocumentIndex = openDocuments.firstIndex(where: { $0.fileURL == fileURL })
        let content: String

        if let openDocumentIndex {
            if activeDocumentIndex == openDocumentIndex {
                snapshotActiveDocument()
                content = currentFileText
            } else {
                content = openDocuments[openDocumentIndex].text
            }
        } else {
            guard let data = try? Data(contentsOf: fileURL),
                  let diskContent = String(data: data, encoding: .utf8) else {
                DiagnosticLog.log("Failed to read backlink source: \(fileURL.lastPathComponent)")
                return false
            }
            content = diskContent
        }

        guard let updatedContent = Self.replacingFirstUnlinkedMention(
            in: content,
            matching: searchTerm,
            linkTarget: linkTarget,
            atLine: lineNumber
        ) else {
            return false
        }

        do {
            try updatedContent.write(to: fileURL, atomically: true, encoding: .utf8)

            if let openDocumentIndex {
                openDocuments[openDocumentIndex].text = updatedContent
                openDocuments[openDocumentIndex].lastSavedText = updatedContent

                if activeDocumentIndex == openDocumentIndex {
                    currentFileURL = fileURL
                    currentFileText = updatedContent
                    lastSavedText = updatedContent
                    isDirty = false
                }
            }

            return true
        } catch {
            DiagnosticLog.log("Failed to write backlink source: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Save

    @discardableResult
    func saveCurrentFile() -> Bool {
        guard activeDocumentIndex != nil else { return true }
        snapshotActiveDocument()
        guard let idx = activeDocumentIndex else { return true }
        return saveDocument(at: idx, treatCancelAsFailure: false)
    }

    private func saveDocument(at index: Int, treatCancelAsFailure: Bool) -> Bool {
        let doc = openDocuments[index]

        if doc.isUntitled {
            return saveUntitledDocument(at: index, treatCancelAsFailure: treatCancelAsFailure)
        }

        guard let url = doc.fileURL, doc.isDirty else { return true }
        do {
            try doc.text.write(to: url, atomically: true, encoding: .utf8)
            openDocuments[index].lastSavedText = doc.text

            let finalURL: URL
            if let renamedURL = UntitledRename.proposedRenameURL(for: url, text: doc.text) {
                do {
                    try CoordinatedFileIO.move(from: url, to: renamedURL)
                    rewriteMovedItemReferences(from: url, to: renamedURL)
                    finalURL = renamedURL
                    DiagnosticLog.log("Auto-renamed \(url.lastPathComponent) → \(renamedURL.lastPathComponent)")
                } catch {
                    DiagnosticLog.log("Auto-rename failed for \(url.lastPathComponent): \(error.localizedDescription)")
                    finalURL = url
                }
            } else {
                finalURL = url
            }

            if activeDocumentIndex == index {
                currentFileURL = finalURL
                currentFileText = doc.text
                lastSavedText = doc.text
                isDirty = false
                if finalURL != url {
                    persistLastOpenFile(finalURL)
                }
            }

            addToRecents(finalURL)
            return true
        } catch {
            DiagnosticLog.log("Failed to save file: \(error.localizedDescription)")
            return false
        }
    }

    private func saveUntitledDocument(at index: Int, treatCancelAsFailure: Bool) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.daringFireballMarkdown]
        panel.nameFieldStringValue = openDocuments[index].displayName + ".md"
        panel.prompt = "Save"

        guard panel.runModal() == .OK, let url = panel.url else { return !treatCancelAsFailure }

        do {
            let text = openDocuments[index].text
            try text.write(to: url, atomically: true, encoding: .utf8)
            openDocuments[index].fileURL = url
            openDocuments[index].lastSavedText = text
            openDocuments[index].untitledNumber = nil

            if activeDocumentIndex == index {
                currentFileURL = url
                currentFileText = text
                lastSavedText = text
                isDirty = false
                persistLastOpenFile(url)
            }

            addToRecents(url)
            DiagnosticLog.log("Saved untitled as: \(url.lastPathComponent)")
            return true
        } catch {
            DiagnosticLog.log("Failed to save untitled: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func saveCurrentFileIfDirty() -> Bool {
        autoSaveWork?.cancel()
        autoSaveWork = nil
        guard isDirty else { return true }
        return saveCurrentFile()
    }

    /// Save only if the current doc is file-backed and dirty (used before switching).
    @discardableResult
    private func saveFileBacked() -> Bool {
        autoSaveWork?.cancel()
        autoSaveWork = nil
        guard isDirty, currentFileURL != nil else { return true }
        return saveCurrentFile()
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

    private static func replacingFirstUnlinkedMention(
        in content: String,
        matching searchTerm: String,
        linkTarget: String,
        atLine lineNumber: Int
    ) -> String? {
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let lineIndex = lineNumber - 1
        guard lines.indices.contains(lineIndex) else { return nil }
        guard let range = firstUnlinkedOccurrence(in: lines[lineIndex], matching: searchTerm) else { return nil }

        lines[lineIndex].replaceSubrange(range, with: "[[\(linkTarget)]]")
        return lines.joined(separator: "\n")
    }

    private static func firstUnlinkedOccurrence(in line: String, matching term: String) -> Range<String.Index>? {
        let nsLine = line as NSString
        let wikiRanges = wikiLinkPattern.matches(in: line, range: NSRange(location: 0, length: nsLine.length)).map(\.range)

        var searchStart = line.startIndex
        while let range = line.range(of: term, options: .caseInsensitive, range: searchStart..<line.endIndex) {
            let charRange = NSRange(range, in: line)
            let isInsideWikiLink = wikiRanges.contains {
                $0.location <= charRange.location && NSMaxRange($0) >= NSMaxRange(charRange)
            }

            if !isInsideWikiLink {
                return range
            }

            searchStart = range.upperBound
        }

        return nil
    }

    private func nextTreeBuildGeneration(for locationID: UUID) -> Int {
        let generation = (treeBuildGeneration[locationID] ?? 0) + 1
        treeBuildGeneration[locationID] = generation
        return generation
    }

    private func loadTree(for locationID: UUID, at url: URL, reindex index: VaultIndex? = nil) {
        let generation = nextTreeBuildGeneration(for: locationID)
        let showHidden = showHiddenFiles

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let tree = FileNode.buildTree(at: url, showHiddenFiles: showHidden)
            DispatchQueue.main.async {
                guard let self,
                      self.treeBuildGeneration[locationID] == generation,
                      let idx = self.locations.firstIndex(where: { $0.id == locationID }) else { return }
                self.locations[idx].fileTree = tree
                self.treeRevision += 1
                if let index {
                    self.reindexVault(index)
                }
            }
        }
    }

    // MARK: - Locations

    @discardableResult
    func addLocation(url: URL) -> Bool {
        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            DiagnosticLog.log("Failed to create bookmark for location: \(url.path)")
            return false
        }

        guard url.startAccessingSecurityScopedResource() else {
            DiagnosticLog.log("Failed to access location: \(url.path)")
            return false
        }
        accessedURLs.insert(url)

        let location = BookmarkedLocation(
            url: url,
            bookmarkData: bookmarkData,
            fileTree: [],
            isAccessible: true
        )
        locations.append(location)
        persistLocations()
        startFSStream(for: location)
        openVaultIndex(for: location)

        DiagnosticLog.log("Added location: \(url.lastPathComponent)")
        loadTree(for: location.id, at: url)

        if !UserDefaults.standard.bool(forKey: Self.hasEverAddedLocationKey) {
            UserDefaults.standard.set(true, forKey: Self.hasEverAddedLocationKey)
        }
        return true
    }

    /// On first-ever location add, creates a Getting Started document and opens it.
    func handleFirstLocationIfNeeded(folderURL: URL) {
        guard !UserDefaults.standard.bool(forKey: Self.hasDeliveredGettingStartedKey) else { return }
        showSidebar()

        let fileName = "Getting Started.md"
        let fileURL = folderURL.appendingPathComponent(fileName)

        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            UserDefaults.standard.set(true, forKey: Self.hasDeliveredGettingStartedKey)
            _ = openFile(at: fileURL)
            return
        }

        guard let bundledURL = Bundle.main.url(forResource: "getting-started", withExtension: "md"),
              let content = try? String(contentsOf: bundledURL, encoding: .utf8) else {
            DiagnosticLog.log("Failed to load getting-started.md from bundle")
            return
        }

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            UserDefaults.standard.set(true, forKey: Self.hasDeliveredGettingStartedKey)
            DiagnosticLog.log("Created Getting Started.md in \(folderURL.lastPathComponent)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                _ = self?.openFile(at: fileURL)
            }
        } catch {
            DiagnosticLog.log("Failed to write Getting Started.md: \(error.localizedDescription)")
        }
    }

    func removeLocation(_ location: BookmarkedLocation) {
        stopFSStream(for: location.id)
        treeBuildGeneration.removeValue(forKey: location.id)
        vaultIndexes[location.id]?.close()
        vaultIndexes.removeValue(forKey: location.id)
        vaultIndexRevision += 1
        if accessedURLs.contains(location.url) {
            location.url.stopAccessingSecurityScopedResource()
            accessedURLs.remove(location.url)
        }
        locations.removeAll { $0.id == location.id }
        persistLocations()
    }

    /// Closes any open documents inside `location`, prompting save/discard for dirty
    /// ones, then removes the location. Returns false if the user cancels a prompt.
    @discardableResult
    func removeLocationClosingOpenDocuments(_ location: BookmarkedLocation) -> Bool {
        let locationPath = location.url.standardizedFileURL.path
        let prefix = locationPath.hasSuffix("/") ? locationPath : locationPath + "/"
        let affectedIDs = openDocuments.compactMap { doc -> UUID? in
            guard let docURL = doc.fileURL?.standardizedFileURL else { return nil }
            return docURL.path.hasPrefix(prefix) ? doc.id : nil
        }
        for id in affectedIDs {
            guard closeDocument(id) else { return false }
        }
        removeLocation(location)
        return true
    }

    func refreshTree(for locationID: UUID) {
        refreshWork[locationID]?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  let idx = self.locations.firstIndex(where: { $0.id == locationID }) else { return }
            self.refreshWork.removeValue(forKey: locationID)
            self.loadTree(
                for: locationID,
                at: self.locations[idx].url,
                reindex: self.vaultIndexes[locationID]
            )
        }

        refreshWork[locationID] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
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

    func clearRecents() {
        recentFiles.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.lastOpenFileKey)
        persistRecents()
    }

    func removeFromRecents(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        persistRecents()
    }

    // MARK: - Pinned Files

    func togglePin(_ url: URL) {
        let normalizedURL = url.standardizedFileURL

        if let idx = pinnedFiles.firstIndex(where: { $0.standardizedFileURL == normalizedURL }) {
            pinnedFiles.remove(at: idx)
        } else {
            guard let bookmarkData = try? normalizedURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) else {
                DiagnosticLog.log("Failed to create bookmark for pinned file: \(normalizedURL.path)")
                return
            }

            var isStale = false
            let pinnedURL = (try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ))?.standardizedFileURL ?? normalizedURL

            if !hasExactActiveAccess(to: pinnedURL) {
                if pinnedURL.startAccessingSecurityScopedResource() {
                    accessedURLs.insert(pinnedURL)
                } else if !hasActiveAccess(to: pinnedURL) {
                    DiagnosticLog.log("Failed to access pinned file: \(pinnedURL.path)")
                }
            }

            pinnedFiles.append(pinnedURL)
        }
        persistPinnedFiles()
    }

    func isPinned(_ url: URL) -> Bool {
        pinnedFiles.contains(url)
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

    func renameItem(at url: URL, to newName: String) -> URL? {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: url, to: newURL)
            rewriteMovedItemReferences(from: url, to: newURL)
            DiagnosticLog.log("Renamed: \(url.lastPathComponent) → \(newName)")
            return newURL
        } catch {
            DiagnosticLog.log("Failed to rename: \(error.localizedDescription)")
            return nil
        }
    }

    func moveItem(at sourceURL: URL, into folderURL: URL) -> URL? {
        let destURL = folderURL.appendingPathComponent(sourceURL.lastPathComponent)

        guard !FileManager.default.fileExists(atPath: destURL.path) else {
            DiagnosticLog.log("Move failed — \(sourceURL.lastPathComponent) already exists in \(folderURL.lastPathComponent)")
            return nil
        }

        do {
            try FileManager.default.moveItem(at: sourceURL, to: destURL)
            rewriteMovedItemReferences(from: sourceURL, to: destURL)
            DiagnosticLog.log("Moved: \(sourceURL.lastPathComponent) → \(folderURL.lastPathComponent)/")
            return destURL
        } catch {
            DiagnosticLog.log("Failed to move: \(error.localizedDescription)")
            return nil
        }
    }

    func deleteItem(at url: URL) -> Bool {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            removeDeletedItemReferences(at: url)
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

    /// Returns the freshest available markdown for copy/export actions.
    /// Prefer the in-memory buffer for open docs; fall back to disk for closed files.
    func textForCopy(at url: URL) -> String? {
        if currentFileURL == url {
            return currentFileText
        }
        if let doc = openDocuments.first(where: { $0.fileURL == url }) {
            return doc.text
        }
        return CopyActions.readMarkdown(from: url)
    }

    private func rewriteMovedItemReferences(from sourceURL: URL, to destURL: URL) {
        for idx in openDocuments.indices {
            guard let fileURL = openDocuments[idx].fileURL,
                  let remappedURL = remappedURL(for: fileURL, moving: sourceURL, to: destURL) else { continue }
            openDocuments[idx].fileURL = remappedURL
        }

        if let currentURL = currentFileURL,
           let remappedURL = remappedURL(for: currentURL, moving: sourceURL, to: destURL) {
            currentFileURL = remappedURL
        }

        var recentsChanged = false
        for idx in recentFiles.indices {
            guard let remappedURL = remappedURL(for: recentFiles[idx], moving: sourceURL, to: destURL) else { continue }
            recentFiles[idx] = remappedURL
            recentsChanged = true
        }
        if recentsChanged {
            persistRecents()
        }

        var pinnedChanged = false
        for idx in pinnedFiles.indices {
            guard let remappedURL = remappedURL(for: pinnedFiles[idx], moving: sourceURL, to: destURL) else { continue }
            pinnedFiles[idx] = remappedURL
            pinnedChanged = true
        }
        if pinnedChanged {
            persistPinnedFiles()
        }

        if let currentFileURL {
            persistLastOpenFile(currentFileURL)
        }
    }

    private func removeDeletedItemReferences(at url: URL) {
        let affectedDocumentIDs = openDocuments.compactMap { document -> UUID? in
            guard let fileURL = document.fileURL, isSameOrDescendant(fileURL, of: url) else { return nil }
            return document.id
        }
        for documentID in affectedDocumentIDs {
            removeDocument(documentID)
        }

        let previousRecentCount = recentFiles.count
        recentFiles.removeAll { isSameOrDescendant($0, of: url) }
        if recentFiles.count != previousRecentCount {
            persistRecents()
        }

        let previousPinnedCount = pinnedFiles.count
        pinnedFiles.removeAll { isSameOrDescendant($0, of: url) }
        if pinnedFiles.count != previousPinnedCount {
            persistPinnedFiles()
        }
    }

    private func remappedURL(for candidateURL: URL, moving sourceURL: URL, to destURL: URL) -> URL? {
        let sourcePath = sourceURL.standardizedFileURL.path
        let candidatePath = candidateURL.standardizedFileURL.path

        if candidatePath == sourcePath {
            return destURL.standardizedFileURL
        }

        guard candidatePath.hasPrefix(sourcePath + "/") else { return nil }
        let relativePath = String(candidatePath.dropFirst(sourcePath.count))
        let destPath = destURL.standardizedFileURL.path
        return URL(fileURLWithPath: destPath + relativePath)
    }

    private func isSameOrDescendant(_ candidateURL: URL, of rootURL: URL) -> Bool {
        let rootPath = rootURL.standardizedFileURL.path
        let candidatePath = candidateURL.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    // MARK: - Open Panel (supports both files and folders)

    func showNewFilePanel(defaultFileName: String = "Untitled.md") {
        createUntitledDocument()
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
            let shouldShowGettingStarted = isFirstRun
            guard addLocation(url: url) else { return }
            if shouldShowGettingStarted {
                handleFirstLocationIfNeeded(folderURL: url)
            }
            showSidebar()
            presentMainWindow()
        } else {
            _ = openFile(at: url)
        }
    }

    // MARK: - Folder Icons

    func setFolderIcon(_ iconName: String, for folderPath: String) {
        folderIcons[folderPath] = iconName
        UserDefaults.standard.set(folderIcons, forKey: Self.folderIconsKey)
    }

    func removeFolderIcon(for folderPath: String) {
        folderIcons.removeValue(forKey: folderPath)
        UserDefaults.standard.set(folderIcons, forKey: Self.folderIconsKey)
    }

    // MARK: - Folder Colors

    func setFolderColor(_ colorName: String, for folderPath: String) {
        folderColors[folderPath] = colorName
        UserDefaults.standard.set(folderColors, forKey: Self.folderColorsKey)
    }

    func removeFolderColor(for folderPath: String) {
        folderColors.removeValue(forKey: folderPath)
        UserDefaults.standard.set(folderColors, forKey: Self.folderColorsKey)
    }

    // MARK: - Folder Expansion

    func isFolderExpanded(_ url: URL) -> Bool {
        expandedFolderPaths.contains(url.path)
    }

    func setFolderExpanded(_ expanded: Bool, for url: URL) {
        let changed: Bool
        if expanded {
            changed = expandedFolderPaths.insert(url.path).inserted
        } else {
            changed = expandedFolderPaths.remove(url.path) != nil
        }
        guard changed else { return }
        UserDefaults.standard.set(Array(expandedFolderPaths), forKey: Self.expandedFolderPathsKey)
    }

    func isLocationCollapsed(_ id: String) -> Bool {
        collapsedLocationIDs.contains(id)
    }

    func setLocationCollapsed(_ collapsed: Bool, for id: String) {
        let changed: Bool
        if collapsed {
            changed = collapsedLocationIDs.insert(id).inserted
        } else {
            changed = collapsedLocationIDs.remove(id) != nil
        }
        guard changed else { return }
        UserDefaults.standard.set(Array(collapsedLocationIDs), forKey: Self.collapsedLocationIDsKey)
    }

    // MARK: - Folder Metadata Lookup

    /// Direct folder color lookup (no ancestor walk). Returns nil if unset.
    func folderColor(for url: URL) -> NSColor? {
        guard let name = folderColors[url.path] else { return nil }
        return Theme.folderColor(named: name)
    }

    /// Direct folder icon lookup (no ancestor walk). Returns nil if unset.
    func folderIcon(for url: URL) -> String? {
        folderIcons[url.path]
    }

    /// Walks ancestors of `url` up to — and including — the containing vault
    /// root, returning the closest ancestor's color. Used to inherit a folder
    /// color onto files inside it (Apple Notes–style).
    func effectiveFolderColor(for url: URL) -> NSColor? {
        guard let vaultRoot = containingVaultRoot(for: url) else { return nil }
        var current = url
        while current.path.count >= vaultRoot.path.count {
            if let color = folderColor(for: current) { return color }
            if current.path == vaultRoot.path { return nil }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    private func containingVaultRoot(for url: URL) -> URL? {
        locations.first(where: { url.path == $0.url.path || url.path.hasPrefix($0.url.path + "/") })?.url
    }

    // MARK: - Persistence: Locations

    private func persistLocations() {
        let stored = locations.map { StoredBookmark(id: $0.id, bookmarkData: $0.bookmarkData) }
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.locationBookmarksKey)
        }
        persistVaultsConfig()
    }

    /// Write vault paths to Application Support for MCP binary discovery
    private func persistVaultsConfig() {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let appName = Bundle.main.bundleIdentifier ?? "com.sabotage.clearly"
        let appDir = appSupport.appendingPathComponent(appName)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        let vaultsFile = appDir.appendingPathComponent("vaults.json")
        let paths = locations.map { $0.url.path }
        let data = try? JSONSerialization.data(withJSONObject: ["vaults": paths], options: [.prettyPrinted])
        try? data?.write(to: vaultsFile, options: .atomic)
    }

    private func restoreLocations() {
        guard let data = UserDefaults.standard.data(forKey: Self.locationBookmarksKey),
              let stored = try? JSONDecoder().decode([StoredBookmark].self, from: data) else { return }

        var didMutateStoredBookmarks = false
        for bookmark in stored {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark.bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                didMutateStoredBookmarks = true
                continue
            }

            var bookmarkData = bookmark.bookmarkData
            if isStale {
                if let refreshed = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    bookmarkData = refreshed
                    didMutateStoredBookmarks = true
                }
            }

            guard url.startAccessingSecurityScopedResource() else {
                didMutateStoredBookmarks = true
                continue
            }
            accessedURLs.insert(url)

            let location = BookmarkedLocation(
                id: bookmark.id,
                url: url,
                bookmarkData: bookmarkData,
                fileTree: [],
                isAccessible: true
            )
            locations.append(location)
            startFSStream(for: location)
            openVaultIndex(for: location)
            loadTree(for: bookmark.id, at: url)
        }

        if didMutateStoredBookmarks {
            persistLocations()
        }
        persistVaultsConfig()
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

    // MARK: - Persistence: Pinned Files

    private func persistPinnedFiles() {
        let bookmarks: [Data] = pinnedFiles.compactMap { url in
            try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        UserDefaults.standard.set(bookmarks, forKey: Self.pinnedBookmarksKey)
    }

    private func restorePinnedFiles() {
        guard let bookmarks = UserDefaults.standard.array(forKey: Self.pinnedBookmarksKey) as? [Data] else { return }

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
                let normalizedURL = url.standardizedFileURL
                if isStale {
                    shouldPersist = true
                }
                if !hasExactActiveAccess(to: normalizedURL) {
                    if normalizedURL.startAccessingSecurityScopedResource() {
                        accessedURLs.insert(normalizedURL)
                    } else if !hasActiveAccess(to: normalizedURL) {
                        DiagnosticLog.log("Failed to restore pinned file access: \(normalizedURL.path)")
                    }
                }
                urls.append(normalizedURL)
            } else {
                shouldPersist = true
            }
        }
        pinnedFiles = urls
        if shouldPersist || urls.count != bookmarks.count {
            persistPinnedFiles()
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

    // MARK: - Vault Index

    private func openVaultIndex(for location: BookmarkedLocation) {
        guard let index = try? VaultIndex(locationURL: location.url) else {
            DiagnosticLog.log("Failed to create vault index for: \(location.url.lastPathComponent)")
            return
        }
        vaultIndexes[location.id] = index
        vaultIndexRevision += 1
        reindexVault(index)
    }

    private func reindexAllVaults() {
        for index in vaultIndexes.values {
            reindexVault(index)
        }
    }

    private func reindexVault(_ index: VaultIndex?) {
        let showHiddenFiles = self.showHiddenFiles
        DispatchQueue.global(qos: .utility).async { [weak self, weak index] in
            index?.indexAllFiles(showHiddenFiles: showHiddenFiles)
            DispatchQueue.main.async {
                self?.vaultIndexRevision += 1
            }
        }
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
        refreshWork[locationID]?.cancel()
        refreshWork.removeValue(forKey: locationID)
        treeBuildGeneration.removeValue(forKey: locationID)
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

    // MARK: - Document Helpers

    private var activeDocumentIndex: Int? {
        openDocuments.firstIndex(where: { $0.id == activeDocumentID })
    }

    private func removeDocument(_ id: UUID) {
        guard let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        let wasCurrent = (id == activeDocumentID)

        if wasCurrent {
            autoSaveWork?.cancel()
            autoSaveWork = nil
        }

        openDocuments.remove(at: idx)

        if wasCurrent {
            if openDocuments.isEmpty {
                activeDocumentID = nil
                currentFileURL = nil
                currentFileText = ""
                lastSavedText = ""
                isDirty = false
            } else {
                let nextIndex = min(idx, openDocuments.count - 1)
                activeDocumentID = openDocuments[nextIndex].id
                restoreActiveDocument()
            }
        }
    }

    private func discardChanges(to id: UUID) {
        guard let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        let doc = openDocuments[idx]

        if doc.isUntitled {
            removeDocument(id)
            return
        }

        openDocuments[idx].text = doc.lastSavedText
        if activeDocumentID == id {
            restoreActiveDocument()
        }
    }

    /// Save current stored properties back into the openDocuments array.
    private func snapshotActiveDocument() {
        guard let idx = activeDocumentIndex else { return }
        flushActiveEditorBuffer()
        openDocuments[idx].text = currentFileText
        openDocuments[idx].lastSavedText = lastSavedText
        openDocuments[idx].viewMode = currentViewMode
    }

    private func flushActiveEditorBuffer() {
        let flush = {
            NotificationCenter.default.post(name: .flushEditorBuffer, object: nil)
        }
        if Thread.isMainThread {
            flush()
        } else {
            DispatchQueue.main.sync(execute: flush)
        }
    }

    func liveCurrentFileText() -> String {
        flushActiveEditorBuffer()
        return currentFileText
    }

    /// Restore stored properties from the active document in openDocuments.
    private func restoreActiveDocument() {
        guard let idx = activeDocumentIndex else { return }
        let doc = openDocuments[idx]
        currentFileURL = doc.fileURL
        currentFileText = doc.text
        lastSavedText = doc.lastSavedText
        isDirty = doc.isDirty
        currentViewMode = doc.viewMode
        currentConflictOutcome = doc.conflictOutcome
        if doc.fileURL != nil {
            refreshConflictOutcomeForActiveDocument()
        }
    }

    /// Set the given document as active and sync stored properties.
    private func activateDocument(_ doc: OpenDocument) {
        activeDocumentID = doc.id
        currentFileURL = doc.fileURL
        currentFileText = doc.text
        lastSavedText = doc.lastSavedText
        isDirty = doc.isDirty
        currentViewMode = doc.viewMode
        currentConflictOutcome = doc.conflictOutcome
        if doc.fileURL != nil {
            refreshConflictOutcomeForActiveDocument()
        }
    }

    private func persistLastOpenFile(_ url: URL) {
        if let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmarkData, forKey: Self.lastOpenFileKey)
        }
    }

    private func promptToSaveChanges(for doc: OpenDocument) -> DirtyDocumentDisposition {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Do you want to save changes to \"\(doc.displayName)\"?"
        alert.informativeText = doc.isUntitled
            ? "This document exists only in memory. If you don't save, your changes will be lost."
            : "If you don't save, your changes will be lost."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .cancel
        default:
            return .discard
        }
    }

    private func presentMainWindow() {
        Task { @MainActor in
            WindowRouter.shared.showMainWindow()
        }
    }

    private func showSidebar() {
        Task { @MainActor in
            isSidebarVisible = true
            UserDefaults.standard.set(true, forKey: Self.sidebarVisibleKey)
        }
    }

    private func hasActiveAccess(to url: URL) -> Bool {
        let targetPath = url.standardizedFileURL.path
        return accessedURLs.contains { accessedURL in
            let scopePath = accessedURL.standardizedFileURL.path
            return targetPath == scopePath || targetPath.hasPrefix(scopePath + "/")
        }
    }

    private func hasExactActiveAccess(to url: URL) -> Bool {
        let targetPath = url.standardizedFileURL.path
        return accessedURLs.contains { $0.standardizedFileURL.path == targetPath }
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
