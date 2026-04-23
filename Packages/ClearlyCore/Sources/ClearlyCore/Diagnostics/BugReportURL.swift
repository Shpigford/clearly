import Foundation

public enum BugReportURL {
    public enum Platform: String {
        case macOS = "macOS"
        case iOS = "iOS"
        case iPadOS = "iPadOS"
    }

    public static func build(
        platform _: Platform,
        appVersion: String,
        osVersion: String,
        device: String? = nil,
        repo: String = "Shpigford/clearly"
    ) -> URL {
        var components = URLComponents(string: "https://github.com/\(repo)/issues/new")!
        var items: [URLQueryItem] = [
            .init(name: "template", value: "bug_report.yml"),
            .init(name: "app-version", value: appVersion),
            .init(name: "os-version", value: osVersion),
        ]
        if let device, !device.isEmpty {
            items.append(.init(name: "device", value: device))
        }
        components.queryItems = items
        return components.url!
    }
}
