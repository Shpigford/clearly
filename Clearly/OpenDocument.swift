import Foundation

enum ViewMode: String, CaseIterable {
    case edit
    case preview
}

/// Represents a single document that is currently open in the editor.
/// Can be either file-backed (has a fileURL) or untitled (in-memory only).
struct OpenDocument: Identifiable {
    let id: UUID
    var fileURL: URL?
    var text: String
    var lastSavedText: String
    var untitledNumber: Int?
    var viewMode: ViewMode = .edit

    var isDirty: Bool { text != lastSavedText }
    var isUntitled: Bool { fileURL == nil }

    var displayName: String {
        if let url = fileURL { return url.lastPathComponent }
        if let n = untitledNumber, n > 1 { return "Untitled \(n)" }
        return "Untitled"
    }
}
