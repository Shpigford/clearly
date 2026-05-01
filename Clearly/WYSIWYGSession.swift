import Foundation

/// Shared host-side session state for the Tiptap WYSIWYG bridge. Used by
/// the JS↔Swift bridge to gate stale callbacks (docChanged, getDocument
/// completions) when the user has switched documents or the file changed
/// externally. Kept separate from the view wrapper so non-view code like
/// `WorkspaceManager` can publish document/revision changes without
/// depending on a type declared inside `WYSIWYGView`.
enum WYSIWYGSession {
    private(set) static var currentDocumentID: UUID?
    private(set) static var currentDocumentEpoch: Int = 0

    static func update(documentID: UUID?, epoch: Int) {
        currentDocumentID = documentID
        currentDocumentEpoch = epoch
    }

    static func matches(documentID: UUID?) -> Bool {
        currentDocumentID == documentID
    }

    static func matches(documentID: UUID?, epoch: Int) -> Bool {
        currentDocumentID == documentID && currentDocumentEpoch == epoch
    }
}
