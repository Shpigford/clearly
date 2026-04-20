import Foundation
import WebKit

public enum LocalImageSupport {
    public static let scheme = "clearly-file"

    public static func fileURLKeyFragment(_ fileURL: URL?) -> String {
        fileURL?.path ?? ""
    }

    public static func resolveImageSources(in html: String, relativeTo documentURL: URL?) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(<img\s[^>]*?src\s*=\s*")([^"]+)("[^>]*?>)"#,
            options: .caseInsensitive
        ) else { return html }

        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return html }

        var result = html
        for match in matches.reversed() {
            guard match.numberOfRanges == 4,
                  let prefixRange = Range(match.range(at: 1), in: result),
                  let srcRange = Range(match.range(at: 2), in: result),
                  let suffixRange = Range(match.range(at: 3), in: result) else { continue }

            let src = String(result[srcRange])
            guard let absolutePath = absolutePath(for: src, relativeTo: documentURL) else { continue }

            let encoded = absolutePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? absolutePath
            let newSrc = "\(scheme)://localhost\(encoded)"
            let fullRange = prefixRange.lowerBound..<suffixRange.upperBound
            result.replaceSubrange(fullRange, with: "\(result[prefixRange])\(newSrc)\(result[suffixRange])")
        }

        return result
    }

    private static func absolutePath(for source: String, relativeTo documentURL: URL?) -> String? {
        if source.hasPrefix("http://") || source.hasPrefix("https://") ||
           source.hasPrefix("data:") || source.hasPrefix("\(scheme)://") {
            return nil
        }

        var filePath = source
        if filePath.hasPrefix("file://") {
            filePath = String(filePath.dropFirst("file://".count))
        }
        filePath = filePath.removingPercentEncoding ?? filePath

        if filePath.hasPrefix("/") {
            return filePath
        }

        guard let documentDirectory = documentURL?.deletingLastPathComponent() else {
            return nil
        }

        return documentDirectory.appendingPathComponent(filePath).path
    }
}

public final class LocalImageSchemeHandler: NSObject, WKURLSchemeHandler {
    private static let mimeTypes: [String: String] = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "gif": "image/gif", "webp": "image/webp", "svg": "image/svg+xml",
        "tiff": "image/tiff", "tif": "image/tiff", "bmp": "image/bmp",
        "heic": "image/heic"
    ]

    public override init() {
        super.init()
    }

    public func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let path = url.path.removingPercentEncoding ?? url.path
        guard !path.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let ext = (path as NSString).pathExtension.lowercased()
        let mime = Self.mimeTypes[ext] ?? "application/octet-stream"
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": mime, "Content-Length": "\(data.count)"]
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
