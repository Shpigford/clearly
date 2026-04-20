import Foundation

public enum ViewMode: String, CaseIterable {
    case edit
    case preview
}

/// Represents a single document that is currently open in the editor.
/// Can be either file-backed (has a fileURL) or untitled (in-memory only).
public struct OpenDocument: Identifiable {
    public let id: UUID
    public var fileURL: URL?
    public var text: String
    public var lastSavedText: String
    public var untitledNumber: Int?
    public var viewMode: ViewMode = .edit

    public init(id: UUID = UUID(), fileURL: URL? = nil, text: String = "", lastSavedText: String = "", untitledNumber: Int? = nil, viewMode: ViewMode = .edit) {
        self.id = id
        self.fileURL = fileURL
        self.text = text
        self.lastSavedText = lastSavedText
        self.untitledNumber = untitledNumber
        self.viewMode = viewMode
    }

    public var isDirty: Bool { text != lastSavedText }
    public var isUntitled: Bool { fileURL == nil }

    public var displayName: String {
        if let url = fileURL { return url.lastPathComponent }
        if let n = untitledNumber, n > 1 { return "Untitled \(n)" }
        return "Untitled"
    }
}
