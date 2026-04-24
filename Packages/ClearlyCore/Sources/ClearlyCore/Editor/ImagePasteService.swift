import Foundation

/// Writes pasted/dropped images to disk next to the open `.md` document.
/// Filenames follow `<slug>-<N>.<ext>` with a linear counter derived from
/// sibling files in the same directory. Always coordinated through
/// `CoordinatedFileIO` so the iCloud presenter dance works on iOS.
public enum ImagePasteService {

    public struct WriteResult {
        public let url: URL
        public let markdown: String
    }

    /// Extensions Clearly treats as pastable/droppable image files. Used on
    /// both platforms to filter incoming pasteboard / drop items.
    public static let imageFileExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "svg", "tiff", "tif", "bmp", "heic"
    ]

    /// URL is worth attempting to download as an image when it's HTTP(S) and
    /// either its path ends in a known image extension OR it has no
    /// extension (common for CDN / signed URLs — MIME check decides later).
    public static func isLikelyImageURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return true }
        return imageFileExtensions.contains(ext)
    }

    /// Derive a URL-safe slug from the document's filename stem. Lowercased,
    /// non-alphanumerics collapsed to `-`, capped at 40 chars so the final
    /// image filename stays well under APFS's 255-byte limit even with a
    /// high counter. Falls back to `"image"` for empty input.
    public static func imageSlug(fromDocumentStem stem: String) -> String {
        let sanitized = UntitledRename.sanitizeFilename(stem).lowercased()
        var chars: [Character] = []
        var lastWasDash = false
        for char in sanitized {
            if char.isLetter || char.isNumber {
                chars.append(char)
                lastWasDash = false
            } else if !lastWasDash {
                chars.append("-")
                lastWasDash = true
            }
        }
        var slug = String(chars)
        while slug.hasPrefix("-") { slug.removeFirst() }
        while slug.hasSuffix("-") { slug.removeLast() }
        if slug.count > 40 {
            slug = String(slug.prefix(40))
            while slug.hasSuffix("-") { slug.removeLast() }
        }
        return slug.isEmpty ? "image" : slug
    }

    /// Next collision-free URL of the form `<slug>-<N>.<ext>` in the same
    /// directory as `docURL`. Scans existing siblings for the highest N
    /// matching the prefix and returns N+1.
    public static func nextImageURL(besidesDocumentAt docURL: URL, ext: String = "png") -> URL {
        let parent = docURL.deletingLastPathComponent()
        let stem = (docURL.lastPathComponent as NSString).deletingPathExtension
        let slug = imageSlug(fromDocumentStem: stem)
        let prefix = "\(slug)-"
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
        var maxN = 0
        for name in siblings {
            guard name.hasPrefix(prefix) else { continue }
            guard (name as NSString).pathExtension.lowercased() == ext.lowercased() else { continue }
            let nameStem = (name as NSString).deletingPathExtension
            let suffix = String(nameStem.dropFirst(prefix.count))
            if let n = Int(suffix), n > maxN { maxN = n }
        }
        return parent.appendingPathComponent("\(prefix)\(maxN + 1).\(ext)")
    }

    /// Writes PNG bytes to a sibling file next to `docURL` via coordinated
    /// I/O, returning the resulting URL and the relative-path markdown
    /// token (`![](slug-N.png)`) to insert into the editor.
    public static func writeImageData(_ data: Data,
                                      ext: String,
                                      besidesDocumentAt docURL: URL,
                                      presenter: NSFilePresenter?) throws -> WriteResult {
        let normalizedExt = ext.lowercased().isEmpty ? "png" : ext.lowercased()
        let url = nextImageURL(besidesDocumentAt: docURL, ext: normalizedExt)
        try CoordinatedFileIO.write(data, to: url, presenter: presenter)
        let encoded = url.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.lastPathComponent
        return WriteResult(url: url, markdown: "![](\(encoded))")
    }

    /// Writes PNG bytes to a sibling file next to `docURL` via coordinated
    /// I/O, returning the resulting URL and the relative-path markdown
    /// token (`![](slug-N.png)`) to insert into the editor.
    public static func writePNG(_ pngData: Data,
                                besidesDocumentAt docURL: URL,
                                presenter: NSFilePresenter?) throws -> WriteResult {
        try writeImageData(pngData, ext: "png", besidesDocumentAt: docURL, presenter: presenter)
    }
}
