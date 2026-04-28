import XCTest
@testable import ClearlyCore

final class LimitsTests: XCTestCase {

    func testIsOpenableSizeMeasuresSymlinkTarget() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("limits-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let targetURL = rootURL.appendingPathComponent("target.md")
        FileManager.default.createFile(atPath: targetURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: targetURL)
        try handle.truncate(atOffset: UInt64(Limits.maxOpenableFileSize + 1))
        try handle.close()

        let linkURL = rootURL.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)

        XCTAssertFalse(Limits.isOpenableSize(linkURL))
    }
}
