import Foundation
import MCP
import GRDB

// MARK: - Argument Parsing

let args = CommandLine.arguments

let bundleIdentifier: String
if let bidIdx = args.firstIndex(of: "--bundle-id"), bidIdx + 1 < args.count {
    bundleIdentifier = args[bidIdx + 1]
} else {
    bundleIdentifier = "com.sabotage.clearly"
}

// MARK: - Resolve Vault Paths

// --vault overrides auto-discovery; otherwise read vaults.json from Application Support
var vaultPaths: [String] = []

if let vaultIdx = args.firstIndex(of: "--vault"), vaultIdx + 1 < args.count {
    vaultPaths = [args[vaultIdx + 1]]
} else {
    // Look for vaults.json in the app's Application Support (handles sandbox container path)
    let home = FileManager.default.homeDirectoryForCurrentUser
    let containerPath = home.appendingPathComponent("Library/Containers/\(bundleIdentifier)/Data/Library/Application Support/\(bundleIdentifier)/vaults.json")
    let standardPath = home.appendingPathComponent("Library/Application Support/\(bundleIdentifier)/vaults.json")
    let vaultsFile = FileManager.default.fileExists(atPath: containerPath.path) ? containerPath : standardPath

    if let data = try? Data(contentsOf: vaultsFile),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let paths = json["vaults"] as? [String] {
        vaultPaths = paths
    }
}

if vaultPaths.isEmpty {
    fputs("No vaults found. Either:\n", stderr)
    fputs("  - Open Clearly and add a vault first (auto-detected via ~/.config/clearly/vaults.json)\n", stderr)
    fputs("  - Pass --vault <path> explicitly\n", stderr)
    exit(1)
}

// Filter to paths that exist
vaultPaths = vaultPaths.filter { FileManager.default.fileExists(atPath: $0) }
if vaultPaths.isEmpty {
    fputs("Error: No vault paths exist on disk.\n", stderr)
    exit(1)
}

// MARK: - Open Indexes

var indexes: [(index: VaultIndex, url: URL)] = []
for path in vaultPaths {
    let url = URL(fileURLWithPath: path)
    do {
        let index = try VaultIndex(locationURL: url, bundleIdentifier: bundleIdentifier)
        indexes.append((index, url))
    } catch {
        fputs("Warning: Cannot open index for \(path): \(error)\n", stderr)
    }
}

if indexes.isEmpty {
    fputs("Error: Could not open any vault indexes.\n", stderr)
    fputs("Make sure Clearly has been opened with these vaults at least once.\n", stderr)
    exit(1)
}

// MARK: - Test Mode

if args.contains("--test") {
    for (index, url) in indexes {
        let files = index.allFiles()
        let tags = index.allTags()
        print("Vault: \(url.path)")
        print("  Files indexed: \(files.count)")
        print("  Tags: \(tags.count)")
    }
    print("OK — \(indexes.count) vault(s)")
    exit(0)
}

// MARK: - MCP Server

try await startMCPServer(indexes: indexes)
