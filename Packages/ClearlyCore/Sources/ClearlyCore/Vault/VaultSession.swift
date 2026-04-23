#if os(iOS)
import Foundation
import Combine
import Observation

public enum VaultSessionError: Error, Equatable, Sendable {
    case iCloudUnavailable
    case bookmarkInvalidated
    case readFailed(String)
    case downloadFailed(String)
}

/// iOS-facing vault manager. Owns a single `VaultWatcher`, persists the chosen location
/// to `UserDefaults`, and provides coordinated reads on demand.
///
/// This is the iOS equivalent of the Mac app's `WorkspaceManager`, intentionally narrower:
/// single vault (no multi-location sidebar), flat file list (no hierarchical tree yet),
/// read-only (writes land in Phase 6).
@Observable
@MainActor
public final class VaultSession {
    public static let persistenceKey = "iosVaultLocation"

    public private(set) var currentVault: VaultLocation?
    public private(set) var files: [VaultFile] = []
    public private(set) var isLoading: Bool = false
    public private(set) var error: VaultSessionError?

    /// 0.0…1.0 while a full vault re-index is running. `nil` when idle. Drives the
    /// sidebar progress bar.
    public private(set) var indexProgress: Double?

    /// Navigation stack binding for `SidebarView_iOS`'s `NavigationStack(path:)`. Detail
    /// views (e.g. preview wiki-link taps) can mutate this to push another note.
    public var navigationPath: [VaultFile] = []

    /// Read-only access for consumers that need to query the FTS5 index (search, backlinks).
    /// `nil` until a vault is attached and its index is constructed.
    public var currentIndex: VaultIndex? { index }

    /// Most-recently-opened files, most-recent-first. Capped at 10. Drives the empty-query
    /// state of the quick switcher sheet. Persisted per-vault in UserDefaults.
    public private(set) var recentFiles: [VaultFile] = []

    /// Global flag any iOS view can flip to present the quick-switcher sheet. Lives here
    /// (not in a local `@State`) so `.keyboardShortcut` handlers attached at different
    /// view levels all trigger the same sheet.
    public var isShowingQuickSwitcher: Bool = false

    @ObservationIgnored private var watcher: VaultWatcher?
    @ObservationIgnored private var index: VaultIndex?
    @ObservationIgnored private var indexingTask: Task<Void, Never>?
    @ObservationIgnored private var indexingGeneration: Int = 0
    @ObservationIgnored private var knownFiles: [URL: FileSnapshot] = [:]
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var hasRestoredRecents: Bool = false

    private static let recentsKey = "iosVaultRecentFilesByVault"
    private static let recentsCap = 10

    private struct FileSnapshot: Equatable {
        let modified: Date?
        let isPlaceholder: Bool
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Attach / detach

    public func attach(_ location: VaultLocation) {
        teardown()
        currentVault = location
        error = nil

        let watcher = VaultWatcher(
            rootURL: location.url,
            useCloudQuery: location.kind == .defaultICloud
        )
        self.watcher = watcher

        watcher.$files
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                guard let self else { return }
                self.files = value
                if !self.hasRestoredRecents && !value.isEmpty {
                    self.hasRestoredRecents = true
                    self.restoreRecents()
                }
            }
            .store(in: &cancellables)
        // Debounced to coalesce NSMetadataQuery update storms into a single incremental
        // reindex per burst. The `files` publish above stays immediate so UI doesn't lag.
        watcher.$files
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] value in self?.scheduleIncrementalReindex(for: value) }
            .store(in: &cancellables)
        watcher.$isLoading
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.isLoading = value }
            .store(in: &cancellables)

        watcher.start()
        persist(location)

        if let newIndex = try? VaultIndex(locationURL: location.url) {
            self.index = newIndex
            beginIndexing(using: newIndex)
        } else {
            DiagnosticLog.log("VaultSession: failed to open VaultIndex for \(location.url.lastPathComponent)")
        }
    }

    /// Forget the current vault entirely. Clears persistence; next launch shows welcome.
    public func forgetCurrentVault() {
        teardown()
        clearPersistence()
    }

    /// Internal teardown of the active watcher + security-scoped access. Does NOT touch
    /// persistence — `attach()` calls this as part of switching vaults, and would otherwise
    /// erase the newly-attached vault's persisted record.
    private func teardown() {
        if let current = currentVault, current.kind != .defaultICloud {
            current.url.stopAccessingSecurityScopedResource()
        }
        indexingGeneration += 1
        indexingTask?.cancel()
        indexingTask = nil
        index?.close()
        index = nil
        indexProgress = nil
        knownFiles.removeAll()
        watcher?.stop()
        watcher = nil
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        currentVault = nil
        files = []
        navigationPath = []
        recentFiles = []
        hasRestoredRecents = false
        isShowingQuickSwitcher = false
        isLoading = false
    }

    public func refresh() {
        watcher?.refresh()
    }

    // MARK: - Persistence

    private func persist(_ location: VaultLocation) {
        let stored = StoredVaultLocation(location)
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.persistenceKey)
        }
    }

    private func clearPersistence() {
        defaults.removeObject(forKey: Self.persistenceKey)
    }

    public func restoreFromPersistence() async {
        guard let data = defaults.data(forKey: Self.persistenceKey) else { return }
        guard let stored = try? JSONDecoder().decode(StoredVaultLocation.self, from: data) else {
            clearPersistence()
            return
        }
        do {
            let location = try await VaultLocation.resolve(from: stored)
            attach(location)
        } catch {
            clearPersistence()
            self.error = mapResolveError(error)
        }
    }

    private func mapResolveError(_ error: Error) -> VaultSessionError {
        switch error {
        case VaultLocationError.iCloudUnavailable:
            return .iCloudUnavailable
        case VaultLocationError.bookmarkInvalidated,
             VaultLocationError.bookmarkResolutionFailed,
             VaultLocationError.securityScopeDenied:
            return .bookmarkInvalidated
        default:
            return .readFailed(String(describing: error))
        }
    }

    // MARK: - Reading

    public func readRawText(at url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) { () throws -> String in
            let data = try CoordinatedFileIO.read(at: url)
            return String(decoding: data, as: UTF8.self)
        }.value
    }

    /// Begin downloading an iCloud placeholder and wait until it's current. Best-effort —
    /// polls metadata up to the provided timeout. Honors task cancellation.
    public func ensureDownloaded(_ url: URL, timeout: TimeInterval = 15) async throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if let status = values?.ubiquitousItemDownloadingStatus {
                if status == .current || status == .downloaded {
                    return
                }
            } else {
                return
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        throw VaultSessionError.downloadFailed("Timed out waiting for iCloud download")
    }

    public func clearError() {
        error = nil
    }

    // MARK: - Indexing

    /// Full vault re-index. Runs off-main on a utility queue. For each `.icloud`
    /// placeholder, kicks off `startDownloadingUbiquitousItem` and waits up to 5s;
    /// files that remain placeholders are skipped this pass — the watcher triggers
    /// incremental re-index once the download lands.
    private func beginIndexing(using index: VaultIndex) {
        indexingTask?.cancel()
        indexingGeneration += 1
        let generation = indexingGeneration
        indexProgress = 0.0

        indexingTask = Task.detached(priority: .utility) { [weak self] in
            await index.indexAllFiles(
                downloadPlaceholder: { url in
                    try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                    let deadline = Date().addingTimeInterval(5)
                    while Date() < deadline {
                        if Task.isCancelled { return false }
                        let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                        if let status = values?.ubiquitousItemDownloadingStatus {
                            if status == .current || status == .downloaded {
                                return true
                            }
                        } else {
                            // Not ubiquitous — local file, safe to read immediately.
                            return true
                        }
                        try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                    return false
                },
                progress: { value in
                    Task { @MainActor [weak self, weak index] in
                        guard let self,
                              let index,
                              let currentIndex = self.index,
                              currentIndex === index,
                              self.indexingGeneration == generation else { return }
                        self.indexProgress = value
                    }
                }
            )
            if Task.isCancelled { return }
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                guard let currentIndex = self.index,
                      currentIndex === index,
                      self.indexingGeneration == generation else { return }
                self.indexProgress = nil
                // Catch-up pass: any file that appeared or changed DURING the rebuild
                // got filtered out of `scheduleIncrementalReindex` (because
                // `indexProgress != nil`) and isn't guaranteed to produce another
                // watcher event afterward. Feed the current `files` through
                // incremental now; `updateFile` hash-skips unchanged entries.
                self.scheduleIncrementalReindex(for: self.files)
            }
        }
    }

    /// Debounced incremental re-index driven by `VaultWatcher.$files`. Diffs the incoming
    /// set against `knownFiles`; for each add / remove / modified-date change, calls
    /// `VaultIndex.updateFile(at:)` on a utility queue. `updateFile` already handles
    /// hash-based skip + delete-if-missing semantics (`VaultIndex.swift:157`).
    ///
    /// While a full rebuild is running, this method no-ops and leaves `knownFiles`
    /// untouched. When the rebuild completes, it calls this method once with the
    /// current `files` to catch any changes that landed during the rebuild window.
    private func scheduleIncrementalReindex(for newFiles: [VaultFile]) {
        guard let index = index else { return }

        // Rebuild owns the snapshot while it runs; don't update knownFiles here or the
        // post-rebuild catch-up pass would miss files added mid-rebuild.
        if indexProgress != nil { return }

        let oldKnown = knownFiles
        let newKnown = Dictionary(uniqueKeysWithValues: newFiles.map {
            ($0.url, FileSnapshot(modified: $0.modified, isPlaceholder: $0.isPlaceholder))
        })
        knownFiles = newKnown

        let rootURL = currentVault?.url ?? index.rootURL
        let oldKeys = Set(oldKnown.keys)
        let newKeys = Set(newKnown.keys)
        var changedPaths: [String] = []

        for url in newKeys.subtracting(oldKeys) {
            changedPaths.append(VaultIndex.relativePath(of: url, from: rootURL))
        }
        for url in oldKeys.subtracting(newKeys) {
            changedPaths.append(VaultIndex.relativePath(of: url, from: rootURL))
        }
        for url in newKeys.intersection(oldKeys) {
            if (oldKnown[url] ?? nil) != (newKnown[url] ?? nil) {
                changedPaths.append(VaultIndex.relativePath(of: url, from: rootURL))
            }
        }

        guard !changedPaths.isEmpty else { return }

        Task.detached(priority: .utility) { [weak index] in
            guard let index = index else { return }
            for path in changedPaths {
                if Task.isCancelled { return }
                _ = try? index.updateFile(at: path)
            }
        }
    }

    // MARK: - Wiki-link resolution

    /// Case-insensitive lookup for `[[name]]`-style wiki links. Prefers the FTS5 index
    /// (more accurate — considers every file on disk, not just the watcher's current view)
    /// and falls back to scanning `files` when the index has not caught up yet (e.g. the
    /// file was just created by the watcher but not yet indexed).
    public func resolveWikiLink(name: String) -> VaultFile? {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return nil }

        if let index = index,
           let indexed = index.resolveWikiLink(name: target) {
            let rootURL = currentVault?.url ?? index.rootURL
            let absoluteURL = rootURL.appendingPathComponent(indexed.path)
            if let match = files.first(where: { $0.url.standardizedFileURL == absoluteURL.standardizedFileURL }) {
                return match
            }
            return VaultFile(
                url: absoluteURL,
                name: absoluteURL.lastPathComponent,
                modified: indexed.modifiedAt,
                isPlaceholder: false
            )
        }

        if let byStem = files.first(where: { Self.stem(of: $0.name).lowercased() == target }) {
            return byStem
        }
        return files.first(where: { $0.name.lowercased() == target })
    }

    /// Resolve `[[name]]`, creating an empty `.md` file at the vault root if no match exists.
    /// Returns the `VaultFile` to navigate to. The watcher will replace the provisional
    /// record with a real one on its next refresh tick.
    public func openOrCreate(name: String) async throws -> VaultFile {
        if let existing = resolveWikiLink(name: name) { return existing }
        guard let vault = currentVault else {
            throw VaultSessionError.readFailed("no vault attached")
        }
        let sanitized = Self.sanitizeWikiName(name)
        guard !sanitized.isEmpty else {
            throw VaultSessionError.readFailed("invalid wiki link name")
        }
        let lowered = sanitized.lowercased()
        let filename = lowered.hasSuffix(".md") || FileNode.markdownExtensions.contains(where: { lowered.hasSuffix(".\($0)") })
            ? sanitized
            : "\(sanitized).md"
        let url = vault.url.appendingPathComponent(filename)
        // Guard: a file may exist on disk that the watcher hasn't surfaced in `files` yet
        // (iCloud metadata lag, pending local-walk refresh). Overwriting would destroy
        // its contents with an empty file.
        if FileManager.default.fileExists(atPath: url.path) {
            return VaultFile(url: url, name: filename, modified: nil, isPlaceholder: false)
        }
        try await Task.detached(priority: .userInitiated) {
            try CoordinatedFileIO.write(Data(), to: url)
        }.value
        refresh()
        return VaultFile(url: url, name: filename, modified: Date(), isPlaceholder: false)
    }

    /// Notes.app-style auto-rename: if `file` is currently named `Untitled.md`
    /// (or `Untitled 2.md`, …) and `text` has a meaningful first line, rename
    /// the file to derive its name from that line. Returns the new `VaultFile`
    /// on success, `nil` if no rename was applicable. Once the file has any
    /// other name, this method is a no-op — manual renames stick.
    public func autoRenameUntitledIfApplicable(_ file: VaultFile, basedOn text: String) async -> VaultFile? {
        guard let destURL = UntitledRename.proposedRenameURL(for: file.url, text: text) else {
            return nil
        }
        let newStem = (destURL.lastPathComponent as NSString).deletingPathExtension
        do {
            try await renameFile(file, to: newStem)
        } catch {
            DiagnosticLog.log("auto-rename failed for \(file.name): \(error.localizedDescription)")
            return nil
        }
        return VaultFile(
            url: destURL,
            name: destURL.lastPathComponent,
            modified: Date(),
            isPlaceholder: false
        )
    }

    /// Create an empty `Untitled.md` (or `Untitled 2.md`, `Untitled 3.md`, …) at the
    /// vault root and return the resulting `VaultFile`. The provisional record is
    /// replaced with a real one on the watcher's next refresh tick.
    /// Create a new folder in the vault. `name` is kebab-case-sanitized
    /// before use so folder names stay consistent with file names. Parent
    /// defaults to the vault root; a non-nil parent is validated to live
    /// inside the vault. Throws if the folder already exists or name is
    /// empty after sanitization. Returns the created folder's URL.
    public func createFolder(named name: String, in parent: URL? = nil) async throws -> URL {
        guard let vault = currentVault else {
            throw VaultSessionError.readFailed("no vault attached")
        }
        let cleanName = UntitledRename.sanitizeFilename(name)
        guard !cleanName.isEmpty else {
            throw VaultSessionError.readFailed("folder name is empty")
        }
        let parentURL: URL = {
            guard let parent else { return vault.url }
            let parentPath = parent.standardizedFileURL.path
            let rootPath = vault.url.standardizedFileURL.path
            return parentPath.hasPrefix(rootPath) ? parent : vault.url
        }()
        let folderURL = parentURL.appendingPathComponent(cleanName)
        if FileManager.default.fileExists(atPath: folderURL.path) {
            throw VaultSessionError.readFailed("a folder with that name already exists")
        }
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
        }.value
        refresh()
        return folderURL
    }

    public func createUntitledNote(in parent: URL? = nil) async throws -> VaultFile {
        guard let vault = currentVault else {
            throw VaultSessionError.readFailed("no vault attached")
        }
        // Default to vault root if no parent specified, but only honor the
        // override if the requested parent is inside the vault — defends
        // against stale/external URLs leaking into the create path.
        let target: URL = {
            guard let parent else { return vault.url }
            let standardized = parent.standardizedFileURL.path
            let root = vault.url.standardizedFileURL.path
            return standardized.hasPrefix(root) ? parent : vault.url
        }()
        let url = UntitledRename.nextUntitledURL(in: target)
        let filename = url.lastPathComponent

        try await Task.detached(priority: .userInitiated) {
            try CoordinatedFileIO.write(Data(), to: url)
        }.value
        refresh()
        return VaultFile(url: url, name: filename, modified: Date(), isPlaceholder: false)
    }

    private static func stem(of filename: String) -> String {
        let ns = filename as NSString
        let ext = ns.pathExtension.lowercased()
        if FileNode.markdownExtensions.contains(ext) {
            return ns.deletingPathExtension
        }
        return filename
    }

    private static func sanitizeWikiName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden: Set<Character> = ["/", "\\", ":", "?", "*", "\"", "<", ">", "|"]
        return String(trimmed.filter { !forbidden.contains($0) })
    }

    // MARK: - File operations

    /// Rename a file within the same directory. `newBaseName` is the filename stem
    /// without extension; the original extension is preserved. Throws if the new
    /// name is empty, contains forbidden characters, or a file already exists at
    /// the destination URL. Also prunes the renamed file from `navigationPath`
    /// and from recents, since both are URL-keyed.
    public func renameFile(_ file: VaultFile, to newBaseName: String) async throws {
        let trimmed = newBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw VaultSessionError.readFailed("new name is empty")
        }
        // Strip a trailing markdown extension the user may have typed so we
        // don't produce `note.md.md`, then kebab-case the rest. Filename
        // sanitization is uniform across manual + auto rename paths.
        let preExt: String = {
            let ns = trimmed as NSString
            let typedExt = ns.pathExtension.lowercased()
            if !typedExt.isEmpty && FileNode.markdownExtensions.contains(typedExt) {
                return ns.deletingPathExtension
            }
            return trimmed
        }()
        let stem = UntitledRename.sanitizeFilename(preExt)
        guard !stem.isEmpty else {
            throw VaultSessionError.readFailed("new name is empty")
        }
        let ext = (file.url.pathExtension.isEmpty ? "md" : file.url.pathExtension)
        let parent = file.url.deletingLastPathComponent()
        let destURL = parent.appendingPathComponent("\(stem).\(ext)")
        if destURL.standardizedFileURL == file.url.standardizedFileURL { return }
        if FileManager.default.fileExists(atPath: destURL.path) {
            throw VaultSessionError.readFailed("a file with that name already exists")
        }
        let src = file.url
        try await Task.detached(priority: .userInitiated) {
            try CoordinatedFileIO.move(from: src, to: destURL)
        }.value
        dropFromNavigationPath(file.url)
        dropFromRecents(file.url)
        refresh()
    }

    /// Delete a file from the vault. Prunes from `navigationPath` and recents.
    public func deleteFile(_ file: VaultFile) async throws {
        let url = file.url
        try await Task.detached(priority: .userInitiated) {
            try CoordinatedFileIO.delete(at: url)
        }.value
        dropFromNavigationPath(file.url)
        dropFromRecents(file.url)
        refresh()
    }

    /// Files tagged with `tag` (case-insensitive). Returns an empty array when no
    /// index is attached. Maps each `IndexedFile` back to a `VaultFile` from the
    /// watcher's current list, falling back to a provisional record constructed
    /// from the absolute URL when the watcher hasn't caught up yet.
    public func filesForTag(_ tag: String) -> [VaultFile] {
        guard let index = index else { return [] }
        let rootURL = currentVault?.url ?? index.rootURL
        let byURL: [URL: VaultFile] = Dictionary(
            uniqueKeysWithValues: files.map { ($0.url.standardizedFileURL, $0) }
        )
        return index.filesForTag(tag: tag).map { indexed in
            let absoluteURL = rootURL.appendingPathComponent(indexed.path)
            if let match = byURL[absoluteURL.standardizedFileURL] { return match }
            return VaultFile(
                url: absoluteURL,
                name: absoluteURL.lastPathComponent,
                modified: indexed.modifiedAt,
                isPlaceholder: false
            )
        }
    }

    private func dropFromNavigationPath(_ url: URL) {
        let target = url.standardizedFileURL
        navigationPath.removeAll { $0.url.standardizedFileURL == target }
    }

    private func dropFromRecents(_ url: URL) {
        let target = url.standardizedFileURL
        recentFiles.removeAll { $0.url.standardizedFileURL == target }
        persistRecents()
    }

    // MARK: - Recent files

    /// Record that `file` was just opened. Dedupes by URL, moves to front, trims to cap,
    /// and persists. Called from detail-view load paths after a successful read.
    public func markRecent(_ file: VaultFile) {
        let standardized = file.url.standardizedFileURL
        recentFiles.removeAll { $0.url.standardizedFileURL == standardized }
        recentFiles.insert(file, at: 0)
        if recentFiles.count > Self.recentsCap {
            recentFiles = Array(recentFiles.prefix(Self.recentsCap))
        }
        persistRecents()
    }

    private func vaultKey() -> String? {
        currentVault?.url.standardizedFileURL.path
    }

    private func persistRecents() {
        guard let key = vaultKey() else { return }
        var all = defaults.dictionary(forKey: Self.recentsKey) as? [String: [String]] ?? [:]
        all[key] = recentFiles.map { $0.url.standardizedFileURL.path }
        defaults.set(all, forKey: Self.recentsKey)
    }

    /// Restore recents for the current vault and drop any paths that don't appear in
    /// `files`. Called exactly once per attach, on the first non-empty watcher emission.
    private func restoreRecents() {
        guard let key = vaultKey(),
              let all = defaults.dictionary(forKey: Self.recentsKey) as? [String: [String]],
              let paths = all[key] else {
            recentFiles = []
            return
        }
        let byPath: [String: VaultFile] = Dictionary(
            uniqueKeysWithValues: files.map { ($0.url.standardizedFileURL.path, $0) }
        )
        recentFiles = paths.compactMap { byPath[$0] }
    }
}
#endif
