import Foundation
import ClearlyCore

/// One-shot migration of `UserDefaults` from the v2.5.0 sandboxed container
/// path back into the standard preferences path used by the unsandboxed
/// v2.6.0+ build.
///
/// macOS stores `UserDefaults` for sandboxed apps under
/// `~/Library/Containers/<bundle-id>/Data/Library/Preferences/<bundle-id>.plist`
/// and for unsandboxed apps under `~/Library/Preferences/<bundle-id>.plist`.
/// When the App Sandbox flag flipped between v2.5.0 (sandboxed) and v2.6.0
/// (unsandboxed), `UserDefaults.standard` silently swapped backing files and
/// the user's existing prefs became invisible to the new app — vault list,
/// recents, sidebar state, theme, every `@AppStorage` key.
///
/// On first launch of any build that includes this migrator, read the v2.5.0
/// plist directly off disk and copy the known keys into `UserDefaults.standard`,
/// but only where the destination is unset. That preserves anything the user
/// changed under v2.6.0 (where they re-picked a vault from the welcome screen)
/// and fills in everything else from their v2.5.0 state.
///
/// Bookmark blobs are copied verbatim. The existing `restoreLocations` /
/// `restoreRecents` / `restorePinnedFiles` / `restoreLastFile` /
/// `restoreDocumentSession` paths in `WorkspaceManager` already detect stale
/// security-scoped bookmarks and refresh them — that handles the
/// sandbox-extension token going dead in the unsandboxed binary.
enum UserDefaultsMigrator {

    private static let migratedFlagKey = "didMigrateFromContainer_2_6_1"

    /// Keys to copy from the old container plist into the standard plist.
    /// Includes every primitive pref, every `@AppStorage` key in the app,
    /// and every bookmark-blob key the workspace persists.
    private static let migratableKeys: [String] = [
        // Workspace / sidebar state
        "hasEverAddedLocation",
        "hasDeliveredGettingStarted",
        "sidebarVisible",
        "showHiddenFiles",
        "launchBehavior",
        "folderIcons",
        "folderColors",
        "expandedFolderPaths",
        "collapsedLocationIDs",
        // Editor / preview / UI prefs (@AppStorage)
        "themePreference",
        "editorFontSize",
        "previewFontFamily",
        "contentWidth",
        "hideFrontmatterInPreview",
        "showLineNumbers",
        "showMenuBarIcon",
        "sidebarSize",
        "sidebarTagsExpanded",
        "sidebarPinnedExpanded",
        "sidebarRecentsExpanded",
        "wikiAgentRunner",
        "wikiAgentModel",
        "wikiChatPanelWidth",
        // Editor / detail toggles persisted outside @AppStorage
        "continuousSpellCheckingEnabled",
        "grammarCheckingEnabled",
        "automaticSpellingCorrectionEnabled",
        "outlineVisible",
        "annotationCommentsVisible",
        "backlinksVisible",
        // Bookmark blobs — Data and arrays of Data. Restore* call sites
        // refresh stale bookmarks automatically.
        "locationBookmarks",
        "recentBookmarks",
        "pinnedBookmarks",
        "lastOpenFileURL",
        "documentSession",
    ]

    /// Run the migration if it hasn't run yet. Idempotent. Cheap when
    /// already migrated (single bool read).
    static func runIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migratedFlagKey) else {
            return
        }
        defer {
            UserDefaults.standard.set(true, forKey: migratedFlagKey)
        }

        guard let containerPlist = readContainerPlist() else {
            DiagnosticLog.log("UserDefaultsMigrator: no v2.5.0 container plist; nothing to migrate")
            return
        }

        var copied = 0
        for key in migratableKeys {
            // Don't overwrite values the user has set under v2.6.0+.
            guard UserDefaults.standard.object(forKey: key) == nil else { continue }
            guard let value = containerPlist[key] else { continue }
            UserDefaults.standard.set(value, forKey: key)
            copied += 1
        }
        DiagnosticLog.log("UserDefaultsMigrator: copied \(copied) of \(migratableKeys.count) keys from v2.5.0 container")
    }

    /// Reads the v2.5.0 sandboxed prefs file directly off disk via the
    /// user's REAL home directory. Uses `getpwuid` so this still works if a
    /// future build re-enables the sandbox (`NSHomeDirectory()` would
    /// redirect to the new container in that case).
    private static func readContainerPlist() -> [String: Any]? {
        guard let pw = getpwuid(geteuid()), let dirPtr = pw.pointee.pw_dir else {
            return nil
        }
        let home = String(cString: dirPtr)
        let path = "\(home)/Library/Containers/com.sabotage.clearly/Data/Library/Preferences/com.sabotage.clearly.plist"
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return NSDictionary(contentsOf: URL(fileURLWithPath: path)) as? [String: Any]
    }
}
