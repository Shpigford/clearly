import UIKit
import QuickLookThumbnailing

final class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let sample = readSample(at: request.fileURL)
        let (heading, body) = split(sample: sample)
        let size = request.maximumSize

        let reply = QLThumbnailReply(contextSize: size) { [weak self] in
            self?.draw(heading: heading, body: body, size: size)
            return true
        }
        handler(reply, nil)
    }

    private func readSample(at url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 4096)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private func split(sample: String) -> (heading: String?, body: String) {
        let lines = sample.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        var heading: String?
        var bodyLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if heading == nil, trimmed.hasPrefix("#") {
                heading = trimmed.drop(while: { $0 == "#" || $0 == " " }).description
                continue
            }
            if !trimmed.isEmpty {
                bodyLines.append(trimmed)
            }
            if bodyLines.count >= 12 { break }
        }

        return (heading, bodyLines.joined(separator: "\n"))
    }

    private func draw(heading: String?, body: String, size: CGSize) {
        let bg = UIColor.white
        let fg = UIColor(white: 0.13, alpha: 1.0)
        let dim = UIColor(white: 0.40, alpha: 1.0)

        bg.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))

        // Below ~64pt, text rendering is illegible; leave a clean blank canvas
        // (system folds in the generic doc badge).
        guard size.width >= 64 else { return }

        let inset = max(6, size.width * 0.08)
        var cursorY = inset

        let headingFontSize = max(11, min(size.width * 0.10, 22))
        let bodyFontSize = max(8, min(size.width * 0.055, 12))

        if let heading, !heading.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: headingFontSize, weight: .semibold),
                .foregroundColor: fg
            ]
            let rect = CGRect(x: inset, y: cursorY, width: size.width - inset * 2, height: headingFontSize * 2.2)
            (heading as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs, context: nil)
            cursorY += headingFontSize * 1.8
        }

        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: bodyFontSize, weight: .regular),
            .foregroundColor: dim
        ]
        let bodyRect = CGRect(x: inset, y: cursorY, width: size.width - inset * 2, height: size.height - cursorY - inset)
        (body as NSString).draw(with: bodyRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: bodyAttrs, context: nil)
    }
}
