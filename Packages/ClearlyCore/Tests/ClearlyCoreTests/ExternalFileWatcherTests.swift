import Foundation
import Testing
@testable import ClearlyCore

struct ExternalFileWatcherTests {

    // MARK: - mergeExternalChange policy

    @Test func applyWhenEditorMatchesLastKnownDisk() {
        let decision = mergeExternalChange(disk: "B", currentText: "A", lastKnownDisk: "A")
        #expect(decision == .apply("B"))
    }

    @Test func ignoreEchoWhenDiskMatchesEditor() {
        let decision = mergeExternalChange(disk: "A", currentText: "A", lastKnownDisk: "B")
        #expect(decision == .ignoreEcho)
    }

    @Test func ignoreDirtyWhenEditorDivergedFromLastKnownDisk() {
        let decision = mergeExternalChange(disk: "B", currentText: "A-typed", lastKnownDisk: "A")
        #expect(decision == .ignoreDirty)
    }

    @Test func ignoreEchoWinsOverDirty() {
        let decision = mergeExternalChange(disk: "X", currentText: "X", lastKnownDisk: "Y")
        #expect(decision == .ignoreEcho)
    }

    @Test func applyDeliversFullDiskString() {
        let decision = mergeExternalChange(
            disk: "# new heading\n\nbody",
            currentText: "# old heading\n\nbody",
            lastKnownDisk: "# old heading\n\nbody"
        )
        #expect(decision == .apply("# new heading\n\nbody"))
    }

    // MARK: - ExternalChangeReducer (the stateful glue used by the modifier)

    @Test func reducerAppliesExternalChangeWhenEditorClean() {
        let r = ExternalChangeReducer(initialText: "A")
        #expect(r.observe(disk: "B", currentText: "A") == "B")
        #expect(r.lastKnownDisk == "B")
    }

    @Test func reducerIgnoresEchoFromOwnSave() {
        let r = ExternalChangeReducer(initialText: "A")
        // User typed "Ab" but DocumentGroup hasn't autosaved yet → currentText="Ab".
        // Then autosave fires and presenter sees disk="Ab".
        #expect(r.observe(disk: "Ab", currentText: "Ab") == nil)
        #expect(r.lastKnownDisk == "Ab")
    }

    /// Regression test for the bug where baseline advanced on every keystroke,
    /// making dirty-detection unreachable. The reducer must NOT advance
    /// `lastKnownDisk` from typing — it advances only from observed disk events.
    @Test func reducerPreservesUnsavedTypingAgainstExternalWrite() {
        let r = ExternalChangeReducer(initialText: "A")
        // User has typed "Ab" — autosave hasn't fired yet, baseline still "A".
        // An external writer rewrites disk to "X".
        #expect(r.observe(disk: "X", currentText: "Ab") == nil)
        // Baseline still advances so we see "X" next time.
        #expect(r.lastKnownDisk == "X")
    }

    @Test func reducerAppliesAfterAutosaveCatchesUp() {
        let r = ExternalChangeReducer(initialText: "A")
        // Type "Ab", autosave fires → presenter sees disk="Ab" (echo).
        _ = r.observe(disk: "Ab", currentText: "Ab")
        // Now external writer rewrites disk to "X". Editor is clean against
        // the new baseline "Ab", so apply.
        #expect(r.observe(disk: "X", currentText: "Ab") == "X")
        #expect(r.lastKnownDisk == "X")
    }

    @Test func reducerHandlesRapidBackToBackExternalWrites() {
        let r = ExternalChangeReducer(initialText: "A")
        #expect(r.observe(disk: "B", currentText: "A") == "B")
        // Caller updates editor to "B" (we returned it). Next external write
        // arrives with editor already at "B".
        #expect(r.observe(disk: "C", currentText: "B") == "C")
    }

    // MARK: - Presenter integration

    @Test func externalWriteFiresCallback() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("doc.md")
        try "v1".write(to: url, atomically: true, encoding: .utf8)

        let received = CapturedText()
        let watcher = ExternalFileWatcher(url: url) { text in
            received.set(text)
        }
        defer { watcher.stop() }

        // Let the presenter register before we issue the foreign write.
        try await Task.sleep(nanoseconds: 100_000_000)

        let foreign = NSFileCoordinator()
        var err: NSError?
        foreign.coordinate(writingItemAt: url, options: .forReplacing, error: &err) { resolved in
            try? "v2".write(to: resolved, atomically: true, encoding: .utf8)
        }
        #expect(err == nil)

        // Poll for the callback (presenter callback runs on its own queue).
        let deadline = Date(timeIntervalSinceNow: 3.0)
        while Date() < deadline {
            if received.value == "v2" { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(received.value == "v2")
    }

    @Test func stopHaltsCallbacks() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("doc.md")
        try "v1".write(to: url, atomically: true, encoding: .utf8)

        let received = CapturedText()
        let watcher = ExternalFileWatcher(url: url) { text in
            received.set(text)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        watcher.stop()

        let foreign = NSFileCoordinator()
        var err: NSError?
        foreign.coordinate(writingItemAt: url, options: .forReplacing, error: &err) { resolved in
            try? "v2".write(to: resolved, atomically: true, encoding: .utf8)
        }
        #expect(err == nil)

        // Wait a moment to be sure no late callback sneaks in.
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(received.value == nil)
    }
}

/// Thread-safe holder for the most recent callback string. The presenter's
/// operation queue is non-main, so the test thread reads via the lock.
private final class CapturedText: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: String?

    var value: String? {
        lock.lock(); defer { lock.unlock() }
        return _value
    }

    func set(_ text: String) {
        lock.lock(); defer { lock.unlock() }
        _value = text
    }
}
