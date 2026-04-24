import XCTest
@testable import ClearlyCore

final class KeychainStoreTests: XCTestCase {

    private let testService = "com.sabotage.clearly.wiki.tests-\(UUID().uuidString)"
    private var store: KeychainStore!

    override func setUp() {
        super.setUp()
        store = KeychainStore(service: testService)
    }

    override func tearDown() {
        try? store.remove("a")
        try? store.remove("b")
        super.tearDown()
    }

    func testSetAndGetRoundTrips() throws {
        try skipIfKeychainUnavailable {
            try store.set("secret-alpha", forKey: "a")
            XCTAssertEqual(try store.get("a"), "secret-alpha")
        }
    }

    func testGetReturnsNilForMissing() throws {
        try skipIfKeychainUnavailable {
            XCTAssertNil(try store.get("nope"))
        }
    }

    func testSetOverwritesExistingValue() throws {
        try skipIfKeychainUnavailable {
            try store.set("first", forKey: "a")
            try store.set("second", forKey: "a")
            XCTAssertEqual(try store.get("a"), "second")
        }
    }

    func testRemoveDeletesValue() throws {
        try skipIfKeychainUnavailable {
            try store.set("gone", forKey: "a")
            try store.remove("a")
            XCTAssertNil(try store.get("a"))
        }
    }

    func testHasValueReflectsExistence() throws {
        try skipIfKeychainUnavailable {
            XCTAssertFalse(store.hasValue("a"))
            try store.set("x", forKey: "a")
            XCTAssertTrue(store.hasValue("a"))
        }
    }

    // MARK: - Helpers

    /// Some CI environments run without a signed-in Keychain and fail with
    /// `errSecMissingEntitlement` or similar on every write. Skip those cases
    /// rather than masking real regressions.
    private func skipIfKeychainUnavailable(_ body: () throws -> Void) throws {
        do {
            try body()
        } catch KeychainStore.KeychainError.unhandledStatus(let status) where status == errSecMissingEntitlement {
            throw XCTSkip("Keychain not available in this environment (status \(status))")
        }
    }
}
