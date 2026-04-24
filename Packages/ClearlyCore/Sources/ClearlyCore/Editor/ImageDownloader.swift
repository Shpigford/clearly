import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public enum ImageDownloadError: Error {
    case invalidResponse
    case notAnImage
    case tooLarge
    case decodeFailed
}

public enum ImageDownloader {

    /// Cap downloaded image bytes so a giant URL can't wedge the paste.
    public static let maxBytes: Int64 = 20 * 1024 * 1024

    /// Fetches `url` and returns PNG-encoded bytes. Validates the response's
    /// `Content-Type` starts with `image/`, enforces a 20 MB cap, and
    /// re-encodes via the platform image decoder so HEIC/WebP/etc. all
    /// normalize to PNG for cross-platform rendering in WKWebView.
    public static func fetchImagePNG(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ImageDownloadError.invalidResponse
        }
        if let mime = http.mimeType, !mime.lowercased().hasPrefix("image/") {
            throw ImageDownloadError.notAnImage
        }
        if Int64(data.count) > maxBytes {
            throw ImageDownloadError.tooLarge
        }
        return try encodePNG(from: data)
    }

    #if os(macOS)
    private static func encodePNG(from data: Data) throws -> Data {
        // Route through NSImage so ImageIO decodes HEIC/WebP/etc., then
        // NSBitmapImageRep re-encodes from TIFF.
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw ImageDownloadError.decodeFailed
        }
        return png
    }
    #else
    private static func encodePNG(from data: Data) throws -> Data {
        guard let image = UIImage(data: data), let png = image.pngData() else {
            throw ImageDownloadError.decodeFailed
        }
        return png
    }
    #endif
}
