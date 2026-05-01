import Foundation

/// Lightweight metadata + first-line preview for a note, surfaced by
/// `VaultIndex.summaries(folderRelativePath:recursive:)` to drive the
/// 3-pane Notes-style middle list. Distinct from `IndexedFile` because
/// the list pane needs a derived `title` (H1 fallback to filename) and a
/// `preview` extracted from the FTS5 content column.
public struct NoteSummary: Hashable, Identifiable, Sendable {
    public let url: URL
    public let title: String
    public let modifiedAt: Date
    public let preview: String

    public var id: URL { url }

    public init(url: URL, title: String, modifiedAt: Date, preview: String) {
        self.url = url
        self.title = title
        self.modifiedAt = modifiedAt
        self.preview = preview
    }
}

/// Sort orders supported by the note list pane. Stored as a raw `String`
/// in `@AppStorage`, exposed here so non-UI code (`VaultIndex` queries,
/// helpers) can consume it.
public enum NoteListSortOrder: String, CaseIterable, Identifiable, Sendable {
    case modifiedDesc
    case modifiedAsc
    case titleAsc
    case titleDesc

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .modifiedDesc: "Date Modified"
        case .modifiedAsc: "Date Modified (oldest first)"
        case .titleAsc: "Title"
        case .titleDesc: "Title (Z–A)"
        }
    }
}
