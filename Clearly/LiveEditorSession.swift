import Foundation

/// Shared host-side session state for the live editor bridge.
///
/// This is intentionally separate from `LiveEditorView` so non-view code like
/// `WorkspaceManager` can publish document/revision changes without depending on
/// a type declared inside the AppKit/WebKit view wrapper.
enum LiveEditorSession {
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
