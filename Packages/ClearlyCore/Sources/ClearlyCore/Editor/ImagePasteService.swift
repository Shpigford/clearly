import Foundation

/// Writes pasted/dropped images to disk next to the open `.md` document.
/// Filenames follow `<slug>-<N>.<ext>` with a linear counter derived from
/// sibling files in the same directory.
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
    /// its path ends in a known image extension.
    public static func isLikelyImageURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return imageFileExtensions.contains(url.pathExtension.lowercased())
    }

    /// Derive a URL-safe slug from the document's filename stem.
    public static func imageSlug(fromDocumentStem stem: String) -> String {
        let sanitized = sanitizeFilename(stem).lowercased()
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
    /// directory as `docURL`.
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

    public static func writeImageData(_ data: Data,
                                      ext: String,
                                      besidesDocumentAt docURL: URL) throws -> WriteResult {
        let normalizedExt = ext.lowercased().isEmpty ? "png" : ext.lowercased()
        let url = nextImageURL(besidesDocumentAt: docURL, ext: normalizedExt)
        try data.write(to: url, options: .atomic)
        let encoded = url.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.lastPathComponent
        return WriteResult(url: url, markdown: "![](\(encoded))")
    }

    public static func writePNG(_ pngData: Data, besidesDocumentAt docURL: URL) throws -> WriteResult {
        try writeImageData(pngData, ext: "png", besidesDocumentAt: docURL)
    }

    /// Lightly sanitize a filename stem: strip filesystem-invalid chars,
    /// trim whitespace, drop leading dots, cap at 240 chars (APFS limit
    /// minus headroom for extension and collision suffix).
    private static func sanitizeFilename(_ raw: String) -> String {
        let forbidden: Set<Character> = ["/", "\\", ":", "?", "*", "\"", "<", ">", "|"]
        var result = ""
        for char in raw {
            if forbidden.contains(char) { continue }
            if char.unicodeScalars.contains(where: { $0.value == 0 || $0.properties.generalCategory == .control }) {
                continue
            }
            result.append(char)
        }
        var trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasPrefix(".") { trimmed.removeFirst() }
        if trimmed.count > 240 { trimmed = String(trimmed.prefix(240)) }
        return trimmed
    }
}
