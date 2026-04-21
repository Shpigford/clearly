import Foundation
import Combine

public struct VaultFile: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let modified: Date?
    public let isPlaceholder: Bool

    public init(url: URL, name: String, modified: Date?, isPlaceholder: Bool) {
        self.url = url
        self.name = name
        self.modified = modified
        self.isPlaceholder = isPlaceholder
    }
}

/// Watches a vault directory for `.md` (and related) files. Two backends:
/// - iCloud: `NSMetadataQuery` scoped to ubiquitous documents, with live updates.
/// - Local / user-picked folder: `FileNode.buildTree` on a background queue, refresh-on-demand.
@MainActor
public final class VaultWatcher: NSObject, ObservableObject {
    @Published public private(set) var files: [VaultFile] = []
    @Published public private(set) var isLoading: Bool = false

    public let rootURL: URL
    public let useCloudQuery: Bool

    private var metadataQuery: NSMetadataQuery?
    private var localGeneration: Int = 0

    public init(rootURL: URL, useCloudQuery: Bool) {
        self.rootURL = rootURL
        self.useCloudQuery = useCloudQuery
        super.init()
    }

    deinit {
        // `NotificationCenter.removeObserver(_:)` is thread-safe. We intentionally do NOT
        // touch `metadataQuery` here — `NSMetadataQuery` is not thread-safe and calling
        // `stop()` from a deinit that may run off main is racy. Callers (VaultSession)
        // must call `stop()` explicitly before releasing.
        NotificationCenter.default.removeObserver(self)
    }

    public func start() {
        if useCloudQuery {
            startCloudQuery()
        } else {
            refresh()
        }
    }

    public func stop() {
        NotificationCenter.default.removeObserver(self)
        metadataQuery?.stop()
        metadataQuery = nil
    }

    public func refresh() {
        if useCloudQuery {
            metadataQuery?.disableUpdates()
            reloadFromMetadataQuery()
            metadataQuery?.enableUpdates()
        } else {
            reloadFromLocalWalk()
        }
    }

    // MARK: - Cloud

    private func startCloudQuery() {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(
            format: "%K ENDSWITH[c] '.md' OR %K ENDSWITH[c] '.markdown' OR %K ENDSWITH[c] '.mdx' OR %K ENDSWITH[c] '.txt' OR %K ENDSWITH[c] '.mdown' OR %K ENDSWITH[c] '.mkd' OR %K ENDSWITH[c] '.mkdn' OR %K ENDSWITH[c] '.mdwn'",
            NSMetadataItemFSNameKey, NSMetadataItemFSNameKey, NSMetadataItemFSNameKey, NSMetadataItemFSNameKey,
            NSMetadataItemFSNameKey, NSMetadataItemFSNameKey, NSMetadataItemFSNameKey, NSMetadataItemFSNameKey
        )
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)]

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidUpdate(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: query
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: query
        )

        metadataQuery = query
        isLoading = true
        query.start()
    }

    @objc private func metadataQueryDidUpdate(_ note: Notification) {
        MainActor.assumeIsolated {
            reloadFromMetadataQuery()
        }
    }

    private func reloadFromMetadataQuery() {
        guard let query = metadataQuery else { return }
        let root = rootURL.standardizedFileURL.path
        var entries: [VaultFile] = []
        entries.reserveCapacity(query.resultCount)
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(root) else { continue }
            let name = (item.value(forAttribute: NSMetadataItemFSNameKey) as? String) ?? url.lastPathComponent
            let modified = item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            let isPlaceholder = status != nil
                && status != NSMetadataUbiquitousItemDownloadingStatusCurrent
                && status != NSMetadataUbiquitousItemDownloadingStatusDownloaded
            entries.append(VaultFile(url: url, name: name, modified: modified, isPlaceholder: isPlaceholder))
        }
        entries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        files = entries
        isLoading = false
    }

    // MARK: - Local

    private func reloadFromLocalWalk() {
        localGeneration += 1
        let generation = localGeneration
        let root = rootURL
        isLoading = true
        Task.detached(priority: .utility) { [weak self] in
            let nodes = FileNode.buildTree(at: root, showHiddenFiles: false)
            let flat = flattenToVaultFiles(nodes: nodes)
            await self?.applyLocalWalk(flat, generation: generation)
        }
    }

    private func applyLocalWalk(_ files: [VaultFile], generation: Int) {
        guard localGeneration == generation else { return }
        self.files = files
        self.isLoading = false
    }
}

private func flattenToVaultFiles(nodes: [FileNode]) -> [VaultFile] {
    var out: [VaultFile] = []
    func walk(_ node: FileNode) {
        if let children = node.children {
            for child in children { walk(child) }
        } else {
            let attrs = try? FileManager.default.attributesOfItem(atPath: node.url.path)
            let modified = attrs?[.modificationDate] as? Date
            out.append(VaultFile(url: node.url, name: node.name, modified: modified, isPlaceholder: false))
        }
    }
    for node in nodes { walk(node) }
    out.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    return out
}
