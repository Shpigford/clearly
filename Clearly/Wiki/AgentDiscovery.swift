import Foundation

/// Detects locally-installed agent CLIs that can drive Wiki mode using the
/// user's existing auth. Checks well-known install paths first (faster than
/// shelling out), then falls back to `which` via PATH. Sandboxed Mac builds
/// still see the path because the Mach-O loader resolves absolute paths, not
/// PATH entries.
enum AgentDiscovery {

    /// Candidate for a concrete runner. Absolute path is guaranteed so the
    /// caller can hand it straight to `Process`.
    struct CLI: Equatable {
        let kind: Kind
        let url: URL

        enum Kind: Equatable {
            case claude
            case codex
        }
    }

    static func findClaude() -> CLI? {
        if let url = firstExisting(at: claudeCandidatePaths) {
            return CLI(kind: .claude, url: url)
        }
        if let url = lookupOnPath("claude") {
            return CLI(kind: .claude, url: url)
        }
        return nil
    }

    static func findCodex() -> CLI? {
        if let url = firstExisting(at: codexCandidatePaths) {
            return CLI(kind: .codex, url: url)
        }
        if let url = lookupOnPath("codex") {
            return CLI(kind: .codex, url: url)
        }
        return nil
    }

    // MARK: - Private

    private static var claudeCandidatePaths: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.local/bin/claude",
            "\(home)/Library/Application Support/com.anthropic.claude/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
    }

    private static var codexCandidatePaths: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.local/bin/codex",
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
        ]
    }

    private static func firstExisting(at paths: [String]) -> URL? {
        let fm = FileManager.default
        for path in paths where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static func lookupOnPath(_ name: String) -> URL? {
        let process = Process()
        process.launchPath = "/usr/bin/env"
        process.arguments = ["which", name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty,
              FileManager.default.isExecutableFile(atPath: text)
        else { return nil }
        return URL(fileURLWithPath: text)
    }
}
