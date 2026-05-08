import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Resolve the markdown UTType from the system rather than using `importedAs`,
    /// which can return a different app's claimed type (e.g. app.markedit.md).
    static let daringFireballMarkdown: UTType = UTType("net.daringfireball.markdown") ?? UTType(filenameExtension: "md") ?? .plainText
}

/// `FileDocument` for `.md` files. Owned by `DocumentGroup` on both Mac and iOS;
/// reading/writing the file goes through SwiftUI's document plumbing.
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
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
