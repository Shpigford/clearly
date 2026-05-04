import Foundation
import Testing
@testable import ClearlyCore

struct NavigationGuardTests {
    @Test func cleanFileBackedDocProceeds() {
        let doc = OpenDocument(
            fileURL: URL(fileURLWithPath: "/tmp/x.md"),
            text: "a",
            lastSavedText: "a"
        )
        #expect(NavigationGuard.decide(for: doc) == .proceed)
    }

    @Test func cleanUntitledDocProceeds() {
        let doc = OpenDocument(fileURL: nil, text: "", lastSavedText: "")
        #expect(NavigationGuard.decide(for: doc) == .proceed)
    }

    @Test func dirtyFileBackedDocSilentSaves() {
        let doc = OpenDocument(
            fileURL: URL(fileURLWithPath: "/tmp/x.md"),
            text: "edited",
            lastSavedText: "original"
        )
        #expect(NavigationGuard.decide(for: doc) == .silentSave)
    }

    @Test func dirtyUntitledDocPromptsUser() {
        let doc = OpenDocument(fileURL: nil, text: "draft", lastSavedText: "")
        #expect(NavigationGuard.decide(for: doc) == .promptUser)
    }

    @Test func noActiveDocProceeds() {
        #expect(NavigationGuard.decide(for: nil) == .proceed)
    }
}
