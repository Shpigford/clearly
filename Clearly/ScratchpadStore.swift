import Foundation
import AppKit
import SwiftUI
import ClearlyCore

struct ScratchpadNote: Identifiable, Hashable {
    var url: URL
    var createdAt: Date
    var modifiedAt: Date
    var lastOpenedAt: Date
    var title: String
    var preview: String

    var id: URL { url }

    static let titlePlaceholder = "New Scratchpad"
}

struct ScratchpadDeleteToken: Equatable {
    var url: URL
    var contents: String
    var createdAt: Date
    var lastOpenedAt: Date
    var title: String
}

@MainActor
@Observable
final class ScratchpadStore {
    static let shared = ScratchpadStore()

    private(set) var notes: [ScratchpadNote] = []
    let directory: URL

    private var pendingWrites: [URL: DispatchWorkItem] = [:]
    private var pendingTexts: [URL: String] = [:]
    private let debounceSeconds: TimeInterval = 0.4

    private init() {
        let fm = FileManager.default
        let base: URL = {
            if let url = try? fm.url(for: .applicationSupportDirectory,
                                     in: .userDomainMask,
                                     appropriateFor: nil,
                                     create: true) {
                return url
            }
            return fm.temporaryDirectory
        }()
        self.directory = base.appendingPathComponent("Scratchpads", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        refresh()
    }

    // MARK: - Refresh

    func refresh() {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey, .isRegularFileKey, .fileSizeKey]
        let urls = (try? fm.contentsOfDirectory(at: directory,
                                                includingPropertiesForKeys: keys,
                                                options: [.skipsHiddenFiles])) ?? []
        var result: [ScratchpadNote] = []
        for url in urls where url.pathExtension.lowercased() == "md" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let modifiedAt = values.contentModificationDate ?? Date()
            let createdAt = createdDate(from: url) ?? values.creationDate ?? modifiedAt
            let lastOpenedAt = lastOpenedDate(for: url) ?? modifiedAt
            let (title, preview) = titleAndPreview(for: url)
            result.append(ScratchpadNote(
                url: url,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                lastOpenedAt: lastOpenedAt,
                title: title,
                preview: preview
            ))
        }
        result.sort { $0.lastOpenedAt > $1.lastOpenedAt }
        notes = result
    }

    // MARK: - Title derivation

    static func deriveTitleAndPreview(from text: String) -> (title: String, preview: String) {
        var title = ""
        var preview = ""
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let stripped = stripLeadingHashes(trimmed)
            if title.isEmpty {
                title = stripped
            } else {
                preview = stripped
                break
            }
        }
        if title.isEmpty { title = ScratchpadNote.titlePlaceholder }
        return (String(title.prefix(80)), String(preview.prefix(120)))
    }

    private static func stripLeadingHashes(_ s: String) -> String {
        var hashes = 0
        for ch in s {
            if ch == "#" { hashes += 1 } else { break }
        }
        guard hashes > 0, hashes <= 6 else { return s }
        let body = s.dropFirst(hashes)
        return body.trimmingCharacters(in: .whitespaces)
    }

    private func titleAndPreview(for url: URL) -> (String, String) {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return (ScratchpadNote.titlePlaceholder, "")
        }
        let prefix = data.prefix(4096)
        let text = String(data: prefix, encoding: .utf8) ?? ""
        return Self.deriveTitleAndPreview(from: text)
    }

    // MARK: - Filename / metadata helpers

    private static let filenameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private func makeFilename(for date: Date) -> String {
        let stamp = Self.filenameDateFormatter.string(from: date)
        let slug = randomSlug()
        return "\(stamp)-\(slug).md"
    }

    private func randomSlug() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }

    private func createdDate(from url: URL) -> Date? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let dash = name.firstIndex(of: "-") else { return nil }
        let stamp = String(name[..<dash])
        return Self.filenameDateFormatter.date(from: stamp)
    }

    // MARK: - Last-opened tracking

    private static func lastOpenedKey(for url: URL) -> String {
        "scratchpad.lastOpened.\(url.lastPathComponent)"
    }

    private func lastOpenedDate(for url: URL) -> Date? {
        let interval = UserDefaults.standard.double(forKey: Self.lastOpenedKey(for: url))
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    func touchOpened(_ note: ScratchpadNote) {
        let now = Date()
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastOpenedKey(for: note.url))
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx].lastOpenedAt = now
            notes.sort { $0.lastOpenedAt > $1.lastOpenedAt }
        }
    }

    private func clearLastOpened(for url: URL) {
        UserDefaults.standard.removeObject(forKey: Self.lastOpenedKey(for: url))
    }

    // MARK: - Create / load / write / delete

    @discardableResult
    func create() -> ScratchpadNote {
        let now = Date()
        let url = directory.appendingPathComponent(makeFilename(for: now))
        try? Data().write(to: url, options: .atomic)
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastOpenedKey(for: url))
        let note = ScratchpadNote(
            url: url,
            createdAt: now,
            modifiedAt: now,
            lastOpenedAt: now,
            title: ScratchpadNote.titlePlaceholder,
            preview: ""
        )
        notes.insert(note, at: 0)
        return note
    }

    @discardableResult
    func ensureNonEmpty() -> ScratchpadNote {
        if let first = notes.first { return first }
        return create()
    }

    func loadText(for note: ScratchpadNote) -> String {
        if let pending = pendingTexts[note.url] { return pending }
        guard let data = try? Data(contentsOf: note.url) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    func write(text: String, to url: URL) {
        pendingTexts[url] = text
        pendingWrites[url]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.flushWrite(url: url)
            }
        }
        pendingWrites[url] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceSeconds, execute: work)
    }

    func flushPendingWrites() {
        let urls = Array(pendingTexts.keys)
        for url in urls {
            flushWrite(url: url)
        }
    }

    private func flushWrite(url: URL) {
        guard let text = pendingTexts.removeValue(forKey: url) else { return }
        pendingWrites.removeValue(forKey: url)?.cancel()
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            if let idx = notes.firstIndex(where: { $0.url == url }) {
                let (title, preview) = Self.deriveTitleAndPreview(from: text)
                notes[idx].title = title
                notes[idx].preview = preview
                notes[idx].modifiedAt = Date()
            }
        } catch {
            DiagnosticLog.log("Scratchpad write failed for \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    @discardableResult
    func delete(_ note: ScratchpadNote) -> ScratchpadDeleteToken? {
        flushWrite(url: note.url)
        let contents = (try? String(contentsOf: note.url, encoding: .utf8)) ?? ""
        do {
            try FileManager.default.removeItem(at: note.url)
        } catch {
            return nil
        }
        let token = ScratchpadDeleteToken(
            url: note.url,
            contents: contents,
            createdAt: note.createdAt,
            lastOpenedAt: note.lastOpenedAt,
            title: note.title
        )
        clearLastOpened(for: note.url)
        notes.removeAll { $0.id == note.id }
        return token
    }

    func restore(_ token: ScratchpadDeleteToken) {
        do {
            try Data(token.contents.utf8).write(to: token.url, options: .atomic)
        } catch {
            return
        }
        UserDefaults.standard.set(token.lastOpenedAt.timeIntervalSince1970, forKey: Self.lastOpenedKey(for: token.url))
        refresh()
    }

    // MARK: - Search

    func search(_ query: String) -> [ScratchpadNote] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return notes }
        let q = trimmed.lowercased()
        return notes.filter {
            $0.title.lowercased().contains(q) || $0.preview.lowercased().contains(q)
        }
    }

    // MARK: - Retention

    func runRetentionSweep(preserving protectedURLs: Set<URL> = []) {
        let defaults = UserDefaults.standard
        let mode = defaults.string(forKey: "scratchpadRetentionMode") ?? "all"
        switch mode {
        case "age":
            let days = max(1, defaults.object(forKey: "scratchpadRetentionDays") as? Int ?? 90)
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            for note in notes where note.modifiedAt < cutoff && !protectedURLs.contains(note.url) {
                try? FileManager.default.removeItem(at: note.url)
                clearLastOpened(for: note.url)
            }
        case "count":
            let limit = max(1, defaults.object(forKey: "scratchpadRetentionCount") as? Int ?? 100)
            let sorted = notes.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
            let protectedCount = notes.filter { protectedURLs.contains($0.url) }.count
            let unprotectedLimit = max(0, limit - protectedCount)
            var keptUnprotected = 0
            for note in sorted {
                if protectedURLs.contains(note.url) { continue }
                if keptUnprotected < unprotectedLimit {
                    keptUnprotected += 1
                    continue
                }
                try? FileManager.default.removeItem(at: note.url)
                clearLastOpened(for: note.url)
            }
        default:
            break
        }
        refresh()
        if notes.isEmpty { _ = create() }
    }

    // MARK: - Reveal

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }
}
