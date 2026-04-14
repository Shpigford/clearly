import Foundation

struct Backlink: Identifiable {
    let id = UUID()
    let sourceFilename: String
    let sourcePath: String
    let contextLine: String
    let lineNumber: Int
    let vaultRootURL: URL
}

final class BacklinksState: ObservableObject {
    @Published var isVisible: Bool {
        didSet { UserDefaults.standard.set(isVisible, forKey: "backlinksVisible") }
    }
    @Published var backlinks: [Backlink] = []
    @Published var unlinkedMentions: [Backlink] = []
    private(set) var currentFilename: String = ""
    private(set) var currentLinkTarget: String = ""

    private var updateWork: DispatchWorkItem?

    init() {
        self.isVisible = UserDefaults.standard.bool(forKey: "backlinksVisible")
    }

    func toggle() {
        isVisible.toggle()
    }

    func update(for fileURL: URL?, using indexes: [VaultIndex]) {
        updateWork?.cancel()

        guard let fileURL else {
            DispatchQueue.main.async {
                self.backlinks = []
                self.unlinkedMentions = []
                self.currentFilename = ""
                self.currentLinkTarget = ""
            }
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.performUpdate(for: fileURL, using: indexes)
        }
        updateWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func removeUnlinkedMention(_ backlink: Backlink) {
        unlinkedMentions.removeAll { $0.id == backlink.id }
    }

    private func performUpdate(for fileURL: URL, using indexes: [VaultIndex]) {
        var linkedResults: [Backlink] = []
        var unlinkedResults: [Backlink] = []
        var filename = ""
        var linkTarget = ""

        for index in indexes {
            guard let file = index.file(forURL: fileURL) else { continue }
            filename = file.filename
            linkTarget = Self.linkTarget(for: file, using: indexes)

            // Linked mentions
            let links = index.linksTo(fileId: file.id)
            for link in links {
                guard let sourcePath = link.sourcePath else { continue }
                let sourceURL = index.rootURL.appendingPathComponent(sourcePath)
                let contextLine = readContextLine(from: sourceURL, at: link.lineNumber)

                linkedResults.append(Backlink(
                    sourceFilename: link.sourceFilename ?? sourcePath,
                    sourcePath: sourcePath,
                    contextLine: contextLine,
                    lineNumber: link.lineNumber ?? 1,
                    vaultRootURL: index.rootURL
                ))
            }

            // Unlinked mentions
            let mentions = index.unlinkedMentions(for: file.filename, excludingFileId: file.id)
            for mention in mentions {
                // Skip if this file already appears in linked results
                if linkedResults.contains(where: { $0.sourcePath == mention.file.path }) { continue }

                unlinkedResults.append(Backlink(
                    sourceFilename: mention.file.filename,
                    sourcePath: mention.file.path,
                    contextLine: mention.contextLine,
                    lineNumber: mention.lineNumber,
                    vaultRootURL: index.rootURL
                ))
            }
        }

        DispatchQueue.main.async {
            self.currentFilename = filename
            self.currentLinkTarget = linkTarget
            self.backlinks = linkedResults
            self.unlinkedMentions = unlinkedResults
        }
    }

    private func readContextLine(from fileURL: URL, at lineNumber: Int?) -> String {
        guard let lineNumber, lineNumber > 0,
              let data = try? Data(contentsOf: fileURL),
              let content = String(data: data, encoding: .utf8) else {
            return ""
        }
        let lines = content.components(separatedBy: "\n")
        guard lineNumber <= lines.count else { return "" }
        return lines[lineNumber - 1].trimmingCharacters(in: .whitespaces)
    }

    private static func linkTarget(for file: IndexedFile, using indexes: [VaultIndex]) -> String {
        var allFiles: [(filename: String, path: String)] = []
        for index in indexes {
            for indexedFile in index.allFiles() {
                allFiles.append((filename: indexedFile.filename, path: indexedFile.path))
            }
        }

        let duplicateCount = allFiles.reduce(into: 0) { count, indexedFile in
            if indexedFile.filename.localizedCaseInsensitiveCompare(file.filename) == .orderedSame {
                count += 1
            }
        }

        if duplicateCount > 1 {
            let pathWithoutExtension = (file.path as NSString).deletingPathExtension
            let pathDuplicateCount = allFiles.reduce(into: 0) { count, indexedFile in
                if ((indexedFile.path as NSString).deletingPathExtension).localizedCaseInsensitiveCompare(pathWithoutExtension) == .orderedSame {
                    count += 1
                }
            }
            return pathDuplicateCount > 1 ? file.path : pathWithoutExtension
        }

        return file.filename
    }
}
