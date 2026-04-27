#if os(iOS)
import Foundation
import Observation
import SwiftUI

/// Per-vault sidebar folder expansion state. Mirrors Mac's
/// `WorkspaceManager.expandedFolderPaths` pattern: presence in the set means
/// expanded, absence means collapsed (default). Persisted in `UserDefaults`
/// keyed by vault path so each vault remembers its own open folders.
@Observable
@MainActor
public final class IOSExpansionState {

    /// Currently-expanded folder paths (URL.path) for the bound vault.
    public private(set) var expandedFolderPaths: Set<String> = []

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var currentVaultKey: String?

    private static let persistenceKey = "iosExpandedFoldersByVault"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Switch the active vault. Loads its persisted expansion state into memory
    /// and points subsequent `setExpanded` writes at its bucket.
    public func bind(to vaultURL: URL?) {
        let newKey = vaultURL?.standardizedFileURL.path
        guard newKey != currentVaultKey else { return }
        currentVaultKey = newKey
        if let key = newKey,
           let all = defaults.dictionary(forKey: Self.persistenceKey) as? [String: [String]],
           let paths = all[key] {
            expandedFolderPaths = Set(paths)
        } else {
            expandedFolderPaths = []
        }
    }

    public func isExpanded(_ url: URL) -> Bool {
        expandedFolderPaths.contains(url.path)
    }

    public func setExpanded(_ expanded: Bool, for url: URL) {
        let changed: Bool
        if expanded {
            changed = expandedFolderPaths.insert(url.path).inserted
        } else {
            changed = expandedFolderPaths.remove(url.path) != nil
        }
        guard changed else { return }
        persist()
    }

    public func expandedBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { self.isExpanded(url) },
            set: { self.setExpanded($0, for: url) }
        )
    }

    private func persist() {
        guard let key = currentVaultKey else { return }
        var all = (defaults.dictionary(forKey: Self.persistenceKey) as? [String: [String]]) ?? [:]
        all[key] = Array(expandedFolderPaths)
        defaults.set(all, forKey: Self.persistenceKey)
    }
}
#endif
