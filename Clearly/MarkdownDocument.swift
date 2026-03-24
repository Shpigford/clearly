import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Resolve the markdown UTType from the system rather than using `importedAs`,
    /// which can return a different app's claimed type (e.g. app.markedit.md).
    static let daringFireballMarkdown: UTType = UTType("net.daringfireball.markdown") ?? UTType(filenameExtension: "md") ?? .plainText
}

struct MarkdownDocument: FileDocument {
    // Include .text because on some systems net.daringfireball.markdown conforms
    // to public.text rather than public.plain-text, and the Open panel needs an
    // ancestor type that actually matches.
    static var readableContentTypes: [UTType] { [.daringFireballMarkdown, .plainText, .text] }
    static var writableContentTypes: [UTType] { [.daringFireballMarkdown] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
