import Foundation

public enum ConflictResolver {
    public struct Outcome: Sendable {
        public let siblingURL: URL
        public let siblingText: String
        public let currentText: String

        public init(siblingURL: URL, siblingText: String, currentText: String) {
            self.siblingURL = siblingURL
            self.siblingText = siblingText
            self.currentText = currentText
        }
    }

    public enum ResolverError: Error {
        case readFailed
        case decodeFailed
    }

    /// Detects unresolved iCloud conflicts for `url`. If any exist, writes the
    /// first unresolved version as a sibling `name (conflict YYYY-MM-DD device).ext`,
    /// marks every unresolved version resolved, and asks iCloud to stop
    /// redelivering them. Returns nil when there is nothing to resolve.
    public static func resolveIfNeeded(at url: URL, presenter: NSFilePresenter?) throws -> Outcome? {
        guard let versions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !versions.isEmpty
        else { return nil }

        return try resolve(
            versions: versions.map { version in
                PendingVersion(contentsURL: version.url) {
                    version.isResolved = true
                }
            },
            at: url,
            presenter: presenter
        )
    }

    struct PendingVersion {
        let contentsURL: URL
        let markResolved: () -> Void
    }

    static func resolve(
        versions: [PendingVersion],
        at url: URL,
        presenter: NSFilePresenter?,
        removeOtherVersions: Bool = true
    ) throws -> Outcome? {
        guard !versions.isEmpty else { return nil }

        let currentText = try decodeUTF8(at: url)
        let payloads = try versions.map { version in
            let data = try Data(contentsOf: version.contentsURL)
            guard let text = String(data: data, encoding: .utf8) else {
                throw ResolverError.decodeFailed
            }
            return (version: version, data: data, text: text)
        }

        var copiedVersions: [(url: URL, text: String)] = []
        for payload in payloads {
            let target = uniqueSiblingURL(for: url)
            try CoordinatedFileIO.write(payload.data, to: target, presenter: presenter)
            copiedVersions.append((target, payload.text))
        }

        for payload in payloads { payload.version.markResolved() }
        if removeOtherVersions {
            try? NSFileVersion.removeOtherVersionsOfItem(at: url)
        }

        guard let firstCopy = copiedVersions.first else { return nil }
        return Outcome(siblingURL: firstCopy.url, siblingText: firstCopy.text, currentText: currentText)
    }

    // MARK: - Private

    private static func uniqueSiblingURL(for originalURL: URL) -> URL {
        let directory = originalURL.deletingLastPathComponent()
        let base = originalURL.deletingPathExtension().lastPathComponent
        let ext = originalURL.pathExtension
        let datestamp = Self.datestamp(Date())
        let device = PlatformDevice.currentName()
        let core = "\(base) (conflict \(datestamp) \(device))"
        let fm = FileManager.default

        var candidate = directory.appendingPathComponent(core).appendingPathExtension(ext)
        var suffix = 2
        while fm.fileExists(atPath: candidate.path) {
            let name = "\(core) \(suffix)"
            candidate = directory.appendingPathComponent(name).appendingPathExtension(ext)
            suffix += 1
        }
        return candidate
    }

    private static func datestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func decodeUTF8(at url: URL) throws -> String {
        let data = try CoordinatedFileIO.read(at: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ResolverError.decodeFailed
        }
        return text
    }
}
