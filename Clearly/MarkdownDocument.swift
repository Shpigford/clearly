import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Resolve the markdown UTType from the system rather than using `importedAs`,
    /// which can return a different app's claimed type (e.g. app.markedit.md).
    static let daringFireballMarkdown: UTType = UTType("net.daringfireball.markdown") ?? UTType(filenameExtension: "md") ?? .plainText
}
