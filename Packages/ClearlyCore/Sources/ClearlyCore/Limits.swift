import Foundation

public enum Limits {
    public static let maxOpenableFileSize: Int64 = 50_000_000

    public static let maxLocalImageSize: Int64 = 20_000_000

    public static let maxHighlightAllLength: Int = 5_000_000

    public static func isOpenableSize(_ url: URL) -> Bool {
        isFileSize(url, atMost: maxOpenableFileSize)
    }

    public static func isFileSize(_ url: URL, atMost limit: Int64) -> Bool {
        let resolvedURL = url.resolvingSymlinksInPath()
        guard let values = try? resolvedURL.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return true
        }
        return Int64(size) <= limit
    }
}
