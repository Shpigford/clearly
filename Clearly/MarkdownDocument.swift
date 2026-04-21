import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Resolve the markdown UTType from the system rather than using `importedAs`,
    /// which can return a different app's claimed type (e.g. app.markedit.md).
    static let daringFireballMarkdown: UTType = UTType("net.daringfireball.markdown") ?? UTType(filenameExtension: "md") ?? .plainText
}

/// File document wrapper for `.md` files. Used by iOS phases that consume `DocumentGroup` or
/// `FileDocumentConfiguration` (Phase 5's editor binding, Phase 6's coordinated writes). The Mac
/// app manages documents through `WorkspaceManager` and never instantiates this type.
struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] = [.daringFireballMarkdown, .plainText]
    static var writableContentTypes: [UTType] = [.daringFireballMarkdown]

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = String(decoding: data, as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Writes land in Phase 6; Phase 4 is deliberately read-only.
        throw CocoaError(.featureUnsupported)
    }
}
