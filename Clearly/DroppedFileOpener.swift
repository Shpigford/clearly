import AppKit
import UniformTypeIdentifiers
import ClearlyCore

/// Opens markdown files dragged onto a document window (or handed to the app
/// by Finder in a batch) as native window tabs instead of scattered
/// standalone windows.
enum DroppedFileOpener {

    /// File URLs on the pasteboard, but only when every dragged file is one
    /// the app can open. Mixed or non-markdown drags return nil so the caller
    /// falls through to the default behavior (e.g. image drops in the editor).
    static func markdownFileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return nil }
        guard urls.allSatisfy(isOpenableFile) else { return nil }
        return urls
    }

    static func isOpenableFile(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .daringFireballMarkdown) || type.conforms(to: .plainText)
    }

    /// Open `urls` as tabs attached to the drop-target `window`. A single
    /// file dropped on an untitled, unedited document replaces it — the
    /// "empty tab" becomes the dropped document. Multiple files leave the
    /// empty tab alone and just add tabs.
    static func open(_ urls: [URL], droppedOn window: NSWindow) {
        let targetDoc = document(for: window)
        let replaceableDoc: NSDocument? = {
            guard urls.count == 1, let targetDoc,
                  targetDoc.fileURL == nil, !targetDoc.isDocumentEdited else { return nil }
            return targetDoc
        }()
        openSerially(urls, tabbingOnto: window) { openedDocument in
            if openedDocument { replaceableDoc?.close() }
        }
    }

    /// Finder / Dock handed the app several files at once: open them all,
    /// tabbed onto the frontmost document window when one exists, otherwise
    /// grouped together as tabs of the first file's window.
    static func openBatch(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let front = NSApp.orderedWindows.first(where: { document(for: $0) != nil }) {
            openSerially(urls, tabbingOnto: front) { _ in }
            return
        }
        openBatchWithoutAnchor(urls)
    }

    /// Find the first URL that opens successfully, then use its window as the
    /// anchor for the rest of the batch.
    private static func openBatchWithoutAnchor(_ urls: [URL]) {
        guard let url = urls.first else { return }
        let rest = Array(urls.dropFirst())
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { doc, _, error in
            if let error { DiagnosticLog.log("openBatch failed for \(url.lastPathComponent): \(error.localizedDescription)") }
            guard let doc else {
                openBatchWithoutAnchor(rest)
                return
            }
            windowWhenReady(for: doc) { anchor in
                guard let anchor else {
                    openBatchWithoutAnchor(rest)
                    return
                }
                openSerially(rest, tabbingOnto: anchor) { _ in }
            }
        }
    }

    private static func document(for window: NSWindow) -> NSDocument? {
        NSDocumentController.shared.documents.first { doc in
            doc.windowControllers.contains { $0.window === window }
        }
    }

    /// Opens one URL at a time so tab order matches the list order; each new
    /// tab becomes the anchor for the next. Already-open documents are just
    /// brought forward, not re-parented into the tab group.
    private static func openSerially(
        _ urls: [URL],
        tabbingOnto anchor: NSWindow,
        openedDocument: Bool = false,
        completion: @escaping (Bool) -> Void
    ) {
        guard let url = urls.first else { completion(openedDocument); return }
        let rest = Array(urls.dropFirst())
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { doc, alreadyOpen, error in
            if let error { DiagnosticLog.log("drop open failed for \(url.lastPathComponent): \(error.localizedDescription)") }
            guard let doc else {
                openSerially(rest, tabbingOnto: anchor, openedDocument: openedDocument, completion: completion)
                return
            }
            guard !alreadyOpen else {
                openSerially(rest, tabbingOnto: anchor, openedDocument: true, completion: completion)
                return
            }
            windowWhenReady(for: doc) { newWindow in
                if let newWindow, newWindow !== anchor {
                    anchor.addTabbedWindow(newWindow, ordered: .above)
                    newWindow.makeKeyAndOrderFront(nil)
                    openSerially(rest, tabbingOnto: newWindow, openedDocument: true, completion: completion)
                } else {
                    openSerially(
                        rest,
                        tabbingOnto: anchor,
                        openedDocument: openedDocument || newWindow != nil,
                        completion: completion
                    )
                }
            }
        }
    }

    /// SwiftUI's `DocumentGroup` can attach the window controller a runloop
    /// turn after `openDocument`'s completion fires, so poll briefly.
    private static func windowWhenReady(
        for doc: NSDocument,
        attempt: Int = 0,
        _ completion: @escaping (NSWindow?) -> Void
    ) {
        if let window = doc.windowControllers.first?.window {
            completion(window)
        } else if attempt < 20 {
            DispatchQueue.main.async {
                windowWhenReady(for: doc, attempt: attempt + 1, completion)
            }
        } else {
            DiagnosticLog.log("drop open: no window appeared for \(doc.fileURL?.lastPathComponent ?? "untitled")")
            completion(nil)
        }
    }
}
