import Foundation

final class ICloudVaultObserver {
    private let rootURL: URL
    private let query = NSMetadataQuery()
    private let onResultsChanged: ([URL]) -> Void
    private var observers: [NSObjectProtocol] = []
    private(set) var currentFileURLs: [URL] = []

    init(rootURL: URL, onResultsChanged: @escaping ([URL]) -> Void) {
        self.rootURL = rootURL.standardizedFileURL
        self.onResultsChanged = onResultsChanged

        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemPathKey, self.rootURL.path)

        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { [weak self] _ in
                self?.publishResults()
            },
            center.addObserver(
                forName: .NSMetadataQueryDidUpdate,
                object: query,
                queue: .main
            ) { [weak self] _ in
                self?.publishResults()
            },
        ]
    }

    deinit {
        stop()
    }

    func start() {
        guard !query.isStarted else { return }
        query.start()
    }

    func stop() {
        if query.isStarted {
            query.stop()
        }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    func refresh() {
        publishResults()
    }

    private func publishResults() {
        query.disableUpdates()
        defer { query.enableUpdates() }

        currentFileURLs = query.results.compactMap { item in
            guard let metadataItem = item as? NSMetadataItem,
                  let fileURL = metadataItem.value(forAttribute: NSMetadataItemURLKey) as? URL else {
                return nil
            }
            return fileURL.standardizedFileURL
        }

        onResultsChanged(currentFileURLs)
    }
}
