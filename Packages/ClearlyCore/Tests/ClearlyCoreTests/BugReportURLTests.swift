import XCTest
@testable import ClearlyCore

final class BugReportURLTests: XCTestCase {
    func testBuildPrefillsOnlySafeFormFields() throws {
        let url = BugReportURL.build(
            platform: .iOS,
            appVersion: "2.4.0 (240)",
            osVersion: "iOS 18.2",
            device: "iPhone16,1"
        )

        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)

        XCTAssertEqual(item(named: "template", in: items), "bug_report.yml")
        XCTAssertEqual(item(named: "app-version", in: items), "2.4.0 (240)")
        XCTAssertEqual(item(named: "os-version", in: items), "iOS 18.2")
        XCTAssertEqual(item(named: "device", in: items), "iPhone16,1")
        XCTAssertNil(item(named: "labels", in: items))
        XCTAssertNil(item(named: "description", in: items))
    }

    func testBuildOmitsEmptyDevice() throws {
        let url = BugReportURL.build(
            platform: .macOS,
            appVersion: "2.4.0 (240)",
            osVersion: "macOS 26.1",
            device: ""
        )

        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertNil(item(named: "device", in: items))
    }

    private func item(named name: String, in items: [URLQueryItem]) -> String? {
        items.first(where: { $0.name == name })?.value
    }
}
