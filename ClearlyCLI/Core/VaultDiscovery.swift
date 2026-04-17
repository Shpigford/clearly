import Foundation

enum VaultDiscovery {
    static func discover(bundleID: String) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let containerPath = home.appendingPathComponent(
            "Library/Containers/\(bundleID)/Data/Library/Application Support/\(bundleID)/vaults.json"
        )
        let standardPath = home.appendingPathComponent(
            "Library/Application Support/\(bundleID)/vaults.json"
        )
        let vaultsFile = FileManager.default.fileExists(atPath: containerPath.path)
            ? containerPath
            : standardPath

        guard let data = try? Data(contentsOf: vaultsFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let paths = json["vaults"] as? [String]
        else {
            return []
        }
        return paths
    }
}
