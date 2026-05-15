import Foundation

/// Watches a single file URL for out-of-process modifications via
/// `NSFilePresenter` + `NSFileCoordinator`. Survives atomic-rename writes
/// (the common save-via-temp pattern) because the presenter is keyed on URL,
/// not file descriptor.
///
/// `onExternalChange` is invoked on `presentedItemOperationQueue` (a serial,
/// non-main queue). Callers that need to touch UI state must hop to main
/// themselves — keeping the dispatch decision in the caller makes the watcher
/// trivially testable without driving a run loop.
public final class ExternalFileWatcher: NSObject, NSFilePresenter, @unchecked Sendable {
    public var presentedItemURL: URL?
    public let presentedItemOperationQueue: OperationQueue = {
        let q = OperationQueue()
        q.qualityOfService = .userInitiated
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private let onExternalChange: (String) -> Void
    private var isStopped = false

    public init(url: URL, onExternalChange: @escaping (String) -> Void) {
        self.presentedItemURL = url
        self.onExternalChange = onExternalChange
        super.init()
        NSFileCoordinator.addFilePresenter(self)
    }

    public func stop() {
        guard !isStopped else { return }
        isStopped = true
        NSFileCoordinator.removeFilePresenter(self)
    }

    deinit { stop() }

    public func presentedItemDidChange() {
        guard let url = presentedItemURL else { return }
        var diskText: String?
        var coordErr: NSError?
        NSFileCoordinator(filePresenter: self).coordinate(
            readingItemAt: url, options: [], error: &coordErr
        ) { resolved in
            #if os(iOS)
            let scoped = resolved.startAccessingSecurityScopedResource()
            defer { if scoped { resolved.stopAccessingSecurityScopedResource() } }
            #endif
            if let data = try? Data(contentsOf: resolved) {
                diskText = String(decoding: data, as: UTF8.self)
            }
        }
        guard let text = diskText else { return }
        guard !isStopped else { return }
        onExternalChange(text)
    }

    public func presentedItemDidMove(to newURL: URL) {
        presentedItemURL = newURL
    }
}
