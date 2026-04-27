import XCTest
@testable import ClearlyCore

final class FileNodeTests: XCTestCase {

    func testBuildTreeMergesWatcherFilesMissingFromDisk() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let remoteURL = rootURL
            .appendingPathComponent("Projects", isDirectory: true)
            .appendingPathComponent("Remote.md")
        let remoteFile = VaultFile(url: remoteURL, name: "Remote.md", modified: nil, isPlaceholder: true)

        let tree = FileNode.buildTree(at: rootURL, including: [remoteFile])

        XCTAssertEqual(tree.map(\.name), ["Projects"])
        let folder = try XCTUnwrap(tree.first)
        XCTAssertTrue(folder.isDirectory)
        XCTAssertEqual(folder.children?.map(\.name), ["Remote.md"])
    }

    func testBuildTreeDoesNotDuplicateDiskFilesFromWatcher() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let localURL = rootURL.appendingPathComponent("Local.md")
        try Data().write(to: localURL)
        let localFile = VaultFile(url: localURL, name: "Local.md", modified: nil, isPlaceholder: false)

        let tree = FileNode.buildTree(at: rootURL, including: [localFile])

        XCTAssertEqual(tree.filter { $0.name == "Local.md" }.count, 1)
    }
}
