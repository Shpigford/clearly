import XCTest
@testable import ClearlyCore

final class VaultMoverTests: XCTestCase {
    private var tempVault: URL!

    override func setUpWithError() throws {
        tempVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-mover-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempVault, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempVault)
    }

    func testCaseOnlyRenameDoesNotTripDestinationExistsOnCaseInsensitiveVolume() throws {
        try XCTSkipIf(Self.volumeIsCaseSensitive(tempVault), "Case-only collision behavior only applies on case-insensitive volumes.")

        let sourceURL = tempVault.appendingPathComponent("Foo.md")
        try "# Foo\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let index = try VaultIndex(locationURL: tempVault)
        defer { index.close() }
        index.indexAllFiles()
        let oldFile = try XCTUnwrap(index.file(forRelativePath: "Foo.md"))

        try VaultMover.move(
            index: index,
            vaultRootURL: tempVault,
            oldRelativePath: "Foo.md",
            newRelativePath: "foo.md"
        )

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: tempVault.path), ["foo.md"])
        let movedFile = try XCTUnwrap(index.file(forRelativePath: "foo.md"))
        XCTAssertEqual(movedFile.id, oldFile.id)
        XCTAssertNil(index.file(forRelativePath: "Foo.md"))
    }

    private static func volumeIsCaseSensitive(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames ?? false
    }
}
