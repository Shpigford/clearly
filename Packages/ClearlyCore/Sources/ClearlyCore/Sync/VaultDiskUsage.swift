import Foundation

public struct VaultDiskUsage: Sendable, Equatable {
    public let totalBytes: Int64
    public let downloadedBytes: Int64
    public let placeholderCount: Int
    public let totalCount: Int

    public init(totalBytes: Int64, downloadedBytes: Int64, placeholderCount: Int, totalCount: Int) {
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.placeholderCount = placeholderCount
        self.totalCount = totalCount
    }

    public static let empty = VaultDiskUsage(totalBytes: 0, downloadedBytes: 0, placeholderCount: 0, totalCount: 0)

    /// Recursively walk a vault folder, summing file sizes and iCloud download status.
    ///
    /// Always invoke off-main — walks the entire tree via `FileManager.enumerator`.
    /// Honors task cancellation.
    public static func compute(walking url: URL) async -> VaultDiskUsage {
        await Task.detached(priority: .utility) {
            let keys: [URLResourceKey] = [
                .isRegularFileKey,
                .totalFileSizeKey,
                .ubiquitousItemDownloadingStatusKey,
                .isUbiquitousItemKey,
            ]
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else {
                return VaultDiskUsage.empty
            }

            var total: Int64 = 0
            var downloaded: Int64 = 0
            var placeholders = 0
            var count = 0

            for case let fileURL as URL in enumerator {
                if Task.isCancelled { break }
                guard let values = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
                guard values.isRegularFile == true else { continue }
                let size = Int64(values.totalFileSize ?? 0)
                total += size
                count += 1
                if values.isUbiquitousItem == true {
                    let status = values.ubiquitousItemDownloadingStatus
                    let isDownloaded = status == .current || status == .downloaded
                    if isDownloaded {
                        downloaded += size
                    } else {
                        placeholders += 1
                    }
                } else {
                    downloaded += size
                }
            }

            return VaultDiskUsage(
                totalBytes: total,
                downloadedBytes: downloaded,
                placeholderCount: placeholders,
                totalCount: count
            )
        }.value
    }
}
