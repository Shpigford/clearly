import Foundation

/// Represents a single document that is currently open in the editor.
/// Can be either file-backed (has a fileURL) or untitled (in-memory only).
struct OpenDocument: Identifiable {
    let id: UUID
    var fileURL: URL?
    var text: String
    var lastSavedText: String
    var untitledNumber: Int?

    var isDirty: Bool { text != lastSavedText }
    var isUntitled: Bool { fileURL == nil }

    var displayName: String {
        if let url = fileURL { return url.lastPathComponent }
        if let n = untitledNumber, n > 1 {
            return L10n.format(
                "workspace.untitled.numbered",
                defaultValue: "Untitled %@",
                String(n)
            )
        }
        return L10n.string("workspace.untitled.single", defaultValue: "Untitled")
    }
}
