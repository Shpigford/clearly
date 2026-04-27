#if os(iOS)
import Foundation
import Observation
import ClearlyCore

/// One tab in the iPad detail-column tab bar. Owns a live `IOSDocumentSession`
/// from the moment the tab is created until it's closed, so every open tab
/// keeps its `NSFilePresenter` attached — remote-change refresh and conflict
/// detection work across inactive tabs, not just the active one.
@Observable
@MainActor
public final class IPadTab: Identifiable {
    public let id: UUID = UUID()
    public private(set) var file: VaultFile
    public var viewMode: ViewMode = .edit
    public let session: IOSDocumentSession

    /// Per-tab outline + backlinks state. Living on the tab (rather than re-creating
    /// per view mount) means switching tabs keeps previously-parsed heading lists and
    /// backlinks queries warm — no re-parse flash when flipping back to a tab.
    @ObservationIgnored public let outlineState: OutlineState = OutlineState()
    @ObservationIgnored public let backlinksState: BacklinksState = BacklinksState()

    init(file: VaultFile) {
        self.file = file
        self.session = IOSDocumentSession()
    }

    /// Rename/move replacement. The underlying session keeps its presenter
    /// (already retargeted by `handleRemoteMove`); the tab only needs to
    /// refresh its user-visible `file` metadata.
    func replaceFile(_ newFile: VaultFile) {
        self.file = newFile
    }
}

/// iPad-only tab state. iPhone never instantiates this class — it stays on
/// `VaultSession.navigationPath` / `NavigationStack` push/pop.
///
/// Persistence: `{ tabs: [fileURL], activeTabURL }` per-vault under
/// `UserDefaults` key `iosTabsByVault`. Restored once per vault attach on
/// the first non-empty `VaultSession.files` emission.
@Observable
@MainActor
public final class IPadTabController {

    public private(set) var tabs: [IPadTab] = []
    public var activeTabID: UUID?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private weak var vault: VaultSession?
    @ObservationIgnored private var hasRestoredForCurrentVault: Bool = false
    @ObservationIgnored private var currentVaultKey: String?

    private static let persistenceKey = "iosTabsByVault"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var activeTab: IPadTab? {
        guard let id = activeTabID else { return nil }
        return tabs.first(where: { $0.id == id })
    }

    // MARK: - Binding to VaultSession

    /// Call when the root view's environment session changes (app launch or
    /// vault switch). Resets state and primes restore on next file emission.
    public func bind(to vault: VaultSession) {
        self.vault = vault
        let newKey = vaultKey(for: vault)
        if newKey != currentVaultKey {
            // Vault switched (or first bind) — tear down any state from the
            // previous vault. Sessions still attached to files on the old
            // vault would keep presenters registered indefinitely.
            teardownTabs()
            hasRestoredForCurrentVault = false
            currentVaultKey = newKey
        }
    }

    /// Called by the iPad root view once per vault attach on the first
    /// non-empty `VaultSession.files` emission. Mirrors the recents-restore
    /// gating in `VaultSession.attach` (restore runs against a populated
    /// file list so URL lookups actually succeed).
    public func restoreIfNeeded(vault: VaultSession) {
        guard !hasRestoredForCurrentVault else { return }
        guard let key = vaultKey(for: vault) else { return }
        guard !vault.files.isEmpty else { return }
        hasRestoredForCurrentVault = true

        guard let all = defaults.dictionary(forKey: Self.persistenceKey) as? [String: [String: Any]],
              let entry = all[key],
              let paths = entry["tabs"] as? [String] else {
            return
        }

        let byPath: [String: VaultFile] = Dictionary(
            uniqueKeysWithValues: vault.files.map { ($0.url.standardizedFileURL.path, $0) }
        )
        let restoredTabs = paths.compactMap { byPath[$0] }.map { IPadTab(file: $0) }
        guard !restoredTabs.isEmpty else { return }

        tabs = restoredTabs
        let activePath = entry["activeTab"] as? String
        if let activePath, let active = tabs.first(where: { $0.file.url.standardizedFileURL.path == activePath }) {
            activeTabID = active.id
        } else {
            activeTabID = tabs.first?.id
        }

        // Open every restored tab's session so presenters register and conflicts
        // surface. Sessions open in parallel; the active tab's load progress is
        // observable via its own `isLoading` flag.
        let v = vault
        for tab in tabs {
            Task { await tab.session.open(tab.file, via: v) }
        }
    }

    private func teardownTabs() {
        for tab in tabs {
            Task { await tab.session.close() }
        }
        tabs = []
        activeTabID = nil
    }

    // MARK: - Tab actions

    /// Single-document open: close any open document and replace it with `file`.
    /// iPad uses sorted-by-recency sidebar as its "tab bar" — one document
    /// shows in the detail pane at a time. If `file` is already the open
    /// document, no-op (still marks recent + persists for ordering).
    public func openExclusive(_ file: VaultFile) {
        let target = file.url.standardizedFileURL
        let existing = tabs.first(where: { tab in
            let url = (tab.session.file?.url ?? tab.file.url).standardizedFileURL
            return url == target
        })

        // Tear down anything that isn't the target.
        for tab in tabs where tab.id != existing?.id {
            Task { await tab.session.close() }
        }

        if let existing {
            tabs = [existing]
            activeTabID = existing.id
        } else {
            let newTab = IPadTab(file: file)
            tabs = [newTab]
            activeTabID = newTab.id
            if let vault {
                Task { [v = vault] in await newTab.session.open(file, via: v) }
            }
        }
        vault?.markRecent(file)
        persist()
    }

    /// Activate an existing tab for `file` or append a new tab. Used for
    /// sidebar taps, wiki-link navigation, and quick-switcher picks. Matches
    /// against `session.file` first (current URL after any rename) and falls
    /// back to `tab.file` (initial URL) so renames don't cause duplicate tabs.
    public func openOrActivate(_ file: VaultFile) {
        let target = file.url.standardizedFileURL
        if let existing = tabs.first(where: { tab in
            if let current = tab.session.file?.url.standardizedFileURL, current == target { return true }
            return tab.file.url.standardizedFileURL == target
        }) {
            activeTabID = existing.id
            vault?.markRecent(file)
            persist()
            return
        }
        appendNewTab(for: file)
    }

    private func appendNewTab(for file: VaultFile) {
        guard let vault else { return }
        let tab = IPadTab(file: file)
        tabs.append(tab)
        activeTabID = tab.id
        vault.markRecent(file)
        Task { [v = vault] in
            await tab.session.open(file, via: v)
        }
        persist()
    }

    /// Close the active tab. Used by ⌘W. No-op if no active tab.
    public func closeActiveTab() {
        guard let id = activeTabID else { return }
        closeTab(id: id)
    }

    public func closeTab(id: UUID) {
        closeTab(id: id, discardUnsavedChanges: false)
    }

    private func closeTab(id: UUID, discardUnsavedChanges: Bool) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[idx]
        Task { await tab.session.close(discardUnsavedChanges: discardUnsavedChanges) }
        tabs.remove(at: idx)

        if activeTabID == id {
            // Activate neighbor: next if present, otherwise previous, otherwise nil.
            if idx < tabs.count {
                activeTabID = tabs[idx].id
            } else if !tabs.isEmpty {
                activeTabID = tabs[tabs.count - 1].id
            } else {
                activeTabID = nil
            }
        }
        persist()
    }

    public func closeTabs(matching file: VaultFile) {
        let target = file.url.standardizedFileURL
        let ids = tabs.filter { tab in
            if tab.file.url.standardizedFileURL == target { return true }
            return tab.session.file?.url.standardizedFileURL == target
        }.map(\.id)
        for id in ids {
            closeTab(id: id, discardUnsavedChanges: true)
        }
    }

    public func activate(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabID = id
        persist()
    }

    /// Activate the tab at `index` (0-based). Used by ⌘1…⌘9. No-op if out of range.
    public func activate(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        activeTabID = tabs[index].id
        persist()
    }

    // MARK: - File-operation hooks

    /// Walk tabs and copy any URL that `IOSDocumentSession` has been moved to
    /// (via its presenter's `handleRemoteMove`) back onto `IPadTab.file`.
    /// Renames flow through `CoordinatedFileIO.move` → presenter callback →
    /// session updates; without this reconcile the tab bar would keep showing
    /// the old name until the tab was closed, and persistence would store the
    /// old URL (restore would then drop the tab).
    ///
    /// Called from the root view whenever `vault.files` changes — that's when
    /// a just-completed rename becomes visible to the UI layer.
    public func reconcileTabURLs() {
        var changed = false
        for tab in tabs {
            if let sessionFile = tab.session.file,
               sessionFile.url.standardizedFileURL != tab.file.url.standardizedFileURL {
                tab.replaceFile(sessionFile)
                changed = true
            }
        }
        if changed { persist() }
    }

    // MARK: - Persistence

    private func vaultKey(for vault: VaultSession) -> String? {
        vault.currentVault?.url.standardizedFileURL.path
    }

    private func persist() {
        guard let key = currentVaultKey else { return }
        var all = defaults.dictionary(forKey: Self.persistenceKey) as? [String: [String: Any]] ?? [:]
        let paths = tabs.map { currentPath(for: $0) }
        let activePath = activeTab.map { currentPath(for: $0) }
        var entry: [String: Any] = ["tabs": paths]
        if let activePath { entry["activeTab"] = activePath }
        all[key] = entry
        defaults.set(all, forKey: Self.persistenceKey)
    }

    private func currentPath(for tab: IPadTab) -> String {
        (tab.session.file?.url ?? tab.file.url).standardizedFileURL.path
    }
}
#endif
