import XCTest
@testable import ClearlyCore

final class WikiOperationApplierTests: XCTestCase {

    private var vault: URL!

    override func setUpWithError() throws {
        vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("wiki-apply-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: vault)
    }

    // MARK: - Happy paths

    func testAppliesCreate() throws {
        let op = WikiOperation(
            kind: .capture, title: "t", rationale: "r",
            changes: [.create(path: "notes/a.md", contents: "hello")]
        )
        try WikiOperationApplier.apply(op, at: vault)
        XCTAssertEqual(try readFile("notes/a.md"), "hello")
    }

    func testAppliesModify() throws {
        try writeFile("a.md", "before")
        let op = WikiOperation(
            kind: .capture, title: "t", rationale: "r",
            changes: [.modify(path: "a.md", before: "before", after: "after")]
        )
        try WikiOperationApplier.apply(op, at: vault)
        XCTAssertEqual(try readFile("a.md"), "after")
    }

    func testAppliesDelete() throws {
        try writeFile("a.md", "bye")
        let op = WikiOperation(
            kind: .review, title: "t", rationale: "r",
            changes: [.delete(path: "a.md", contents: "bye")]
        )
        try WikiOperationApplier.apply(op, at: vault)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("a.md").path))
    }

    func testAppliesMixedBatch() throws {
        try writeFile("keep.md", "old keep")
        try writeFile("gone.md", "gone")
        let op = WikiOperation(
            kind: .capture, title: "t", rationale: "r",
            changes: [
                .create(path: "new.md", contents: "fresh"),
                .modify(path: "keep.md", before: "old keep", after: "new keep"),
                .delete(path: "gone.md", contents: "gone"),
            ]
        )
        try WikiOperationApplier.apply(op, at: vault)
        XCTAssertEqual(try readFile("new.md"), "fresh")
        XCTAssertEqual(try readFile("keep.md"), "new keep")
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("gone.md").path))
    }

    // MARK: - Precondition failures

    func testRejectsCreateOverExistingFile() throws {
        try writeFile("a.md", "existing")
        let op = WikiOperation(
            kind: .capture, title: "t", rationale: "r",
            changes: [.create(path: "a.md", contents: "new")]
        )
        XCTAssertThrowsError(try WikiOperationApplier.apply(op, at: vault)) { error in
            XCTAssertEqual(error as? WikiOperationApplier.ApplyError, .pathAlreadyExists("a.md"))
        }
        XCTAssertEqual(try readFile("a.md"), "existing", "should not mutate on precheck failure")
    }

    func testRejectsModifyWhenFileMissing() throws {
        let op = WikiOperation(
            kind: .capture, title: "t", rationale: "r",
            changes: [.modify(path: "missing.md", before: "x", after: "y")]
        )
        XCTAssertThrowsError(try WikiOperationApplier.apply(op, at: vault)) { error in
            XCTAssertEqual(error as? WikiOperationApplier.ApplyError, .pathNotFound("missing.md"))
        }
    }

    func testRejectsModifyWhenBaseMismatches() throws {
        try writeFile("a.md", "actual")
        let op = WikiOperation(
            kind: .capture, title: "t", rationale: "r",
            changes: [.modify(path: "a.md", before: "stale", after: "new")]
        )
        XCTAssertThrowsError(try WikiOperationApplier.apply(op, at: vault)) { error in
            XCTAssertEqual(error as? WikiOperationApplier.ApplyError, .modifyBaseMismatch("a.md"))
        }
        XCTAssertEqual(try readFile("a.md"), "actual", "should not mutate on stale base")
    }

    func testRejectsDeleteWhenContentMismatches() throws {
        try writeFile("a.md", "actual")
        let op = WikiOperation(
            kind: .review, title: "t", rationale: "r",
            changes: [.delete(path: "a.md", contents: "stale")]
        )
        XCTAssertThrowsError(try WikiOperationApplier.apply(op, at: vault)) { error in
            XCTAssertEqual(error as? WikiOperationApplier.ApplyError, .deleteContentMismatch("a.md"))
        }
        XCTAssertEqual(try readFile("a.md"), "actual")
    }

    func testRejectsCreateThroughSymlinkEscapingVault() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("wiki-apply-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: vault.appendingPathComponent("linked"),
            withDestinationURL: outside
        )

        let op = WikiOperation(
            kind: .capture, title: "t", rationale: "r",
            changes: [.create(path: "linked/outside.md", contents: "nope")]
        )

        XCTAssertThrowsError(try WikiOperationApplier.apply(op, at: vault)) { error in
            XCTAssertEqual(error as? WikiOperationError, .pathEscapesVault("linked/outside.md"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("outside.md").path))
    }

    func testRejectsDeleteThroughSymlinkEscapingVault() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("wiki-apply-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        let externalFile = outside.appendingPathComponent("secret.md")
        try "keep".write(to: externalFile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: vault.appendingPathComponent("linked"),
            withDestinationURL: outside
        )

        let op = WikiOperation(
            kind: .review, title: "t", rationale: "r",
            changes: [.delete(path: "linked/secret.md", contents: "keep")]
        )

        XCTAssertThrowsError(try WikiOperationApplier.apply(op, at: vault)) { error in
            XCTAssertEqual(error as? WikiOperationError, .pathEscapesVault("linked/secret.md"))
        }
        XCTAssertEqual(try String(contentsOf: externalFile, encoding: .utf8), "keep")
    }

    func testDeleteThroughSymlinkInsideVaultRemovesLinkOnly() throws {
        try writeFile("real.md", "keep")
        let link = vault.appendingPathComponent("link.md")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: vault.appendingPathComponent("real.md")
        )

        let op = WikiOperation(
            kind: .review, title: "t", rationale: "r",
            changes: [.delete(path: "link.md", contents: "keep")]
        )

        try WikiOperationApplier.apply(op, at: vault)
        XCTAssertFalse(FileManager.default.fileExists(atPath: link.path))
        XCTAssertEqual(try readFile("real.md"), "keep")
    }

    // MARK: - Loose-equal tolerance

    func testAppliesModifyWhenDiskHasTrailingNewlineDrift() throws {
        try writeFile("a.md", "hello\nworld\n")
        let op = WikiOperation(
            kind: .capture, title: "t", rationale: "r",
            // Agent dropped the trailing newline — common LLM drift.
            changes: [.modify(path: "a.md", before: "hello\nworld", after: "hello\nchanged")]
        )
        XCTAssertNoThrow(try WikiOperationApplier.apply(op, at: vault))
        XCTAssertEqual(try readFile("a.md"), "hello\nchanged")
    }

    func testAppliesModifyWhenLineTrailingWhitespaceDiffers() throws {
        try writeFile("a.md", "first line   \nsecond\n")
        let op = WikiOperation(
            kind: .capture, title: "t", rationale: "r",
            // Agent trimmed trailing whitespace on each line.
            changes: [.modify(path: "a.md", before: "first line\nsecond", after: "first line\ndone")]
        )
        XCTAssertNoThrow(try WikiOperationApplier.apply(op, at: vault))
    }

    func testStillRejectsRealContentDivergence() throws {
        try writeFile("a.md", "the user wrote different content")
        let op = WikiOperation(
            kind: .capture, title: "t", rationale: "r",
            changes: [.modify(path: "a.md", before: "original content", after: "new")]
        )
        XCTAssertThrowsError(try WikiOperationApplier.apply(op, at: vault)) { error in
            XCTAssertEqual(error as? WikiOperationApplier.ApplyError, .modifyBaseMismatch("a.md"))
        }
    }

    func testRejectsModifyWhenOnlyLeadingWhitespaceDiffers() throws {
        try writeFile("a.md", "  indented")
        let op = WikiOperation(
            kind: .capture, title: "t", rationale: "r",
            changes: [.modify(path: "a.md", before: "indented", after: "new")]
        )
        XCTAssertThrowsError(try WikiOperationApplier.apply(op, at: vault)) { error in
            XCTAssertEqual(error as? WikiOperationApplier.ApplyError, .modifyBaseMismatch("a.md"))
        }
        XCTAssertEqual(try readFile("a.md"), "  indented")
    }

    // MARK: - Rollback

    func testRollsBackWhenMidApplyFails() throws {
        try writeFile("first.md", "first-before")
        let op = WikiOperation(
            kind: .capture, title: "t", rationale: "r",
            changes: [
                .modify(path: "first.md", before: "first-before", after: "first-after"),
                // Second change precheck passes (no "a.md" yet), but we'll
                // sabotage the write by creating a file at the target path so
                // its intermediate-dir parent is actually a file. To force
                // a mid-apply failure we instead use a create that targets a
                // path whose parent is a regular file — build that below.
                .create(path: "second/conflict.md", contents: "never"),
            ]
        )
        // Make "second" a file, not a directory, so creating "second/conflict.md" fails during apply.
        try writeFile("second", "I am a file, not a folder")

        XCTAssertThrowsError(try WikiOperationApplier.apply(op, at: vault))
        XCTAssertEqual(try readFile("first.md"), "first-before",
                       "the successful modify must be rolled back when later change fails")
    }

    func testRollbackRestoresExactDiskContentsAfterLooseEqualPrecheck() throws {
        try writeFile("first.md", "first-before\n")
        let op = WikiOperation(
            kind: .capture, title: "t", rationale: "r",
            changes: [
                .modify(path: "first.md", before: "first-before", after: "first-after"),
                .create(path: "second/conflict.md", contents: "never"),
            ]
        )
        try writeFile("second", "I am a file, not a folder")

        XCTAssertThrowsError(try WikiOperationApplier.apply(op, at: vault))
        XCTAssertEqual(try readFile("first.md"), "first-before\n",
                       "rollback must restore the exact bytes that were on disk, not the normalized agent preimage")
    }

    func testRollbackRemovesDirectoriesCreatedForCreate() throws {
        try writeFile("blocking", "I am a file, not a folder")
        let op = WikiOperation(
            kind: .capture, title: "t", rationale: "r",
            changes: [
                .create(path: "created/ok.md", contents: "ok"),
                .create(path: "blocking/conflict.md", contents: "never"),
            ]
        )

        XCTAssertThrowsError(try WikiOperationApplier.apply(op, at: vault))
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("created").path),
                       "rollback should remove directories that only existed for the rolled-back create")
    }

    // MARK: - Helpers

    private func writeFile(_ relative: String, _ contents: String) throws {
        let url = vault.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func readFile(_ relative: String) throws -> String {
        try String(contentsOf: vault.appendingPathComponent(relative), encoding: .utf8)
    }
}
