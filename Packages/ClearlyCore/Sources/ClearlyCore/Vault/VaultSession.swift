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

    /// Navigation stack binding for `SidebarView_iOS`'s `NavigationStack(path:)`. Detail
    /// views (e.g. preview wiki-link taps) can mutate this to push another note.
    public var navigationPath: [VaultFile] = []

    @ObservationIgnored private var watcher: VaultWatcher?
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private let defaults: UserDefaults

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
            .sink { [weak self] value in self?.files = value }
            .store(in: &cancellables)
        watcher.$isLoading
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.isLoading = value }
            .store(in: &cancellables)

        watcher.start()
        persist(location)
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
        watcher?.stop()
        watcher = nil
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
        currentVault = nil
        files = []
        navigationPath = []
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

    // MARK: - Wiki-link resolution

    /// Case-insensitive lookup for `[[name]]`-style wiki links against the current vault file list.
    /// Matches by stem (filename without markdown extension) first, then by full filename.
    public func resolveWikiLink(name: String) -> VaultFile? {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return nil }
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
}
#endif
