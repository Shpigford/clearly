import Foundation

/// Detects locally-installed agent CLIs that can drive Wiki mode using the
/// user's existing auth. Checks well-known install paths first (faster than
/// shelling out), then falls back to `which` via PATH. Sandboxed Mac builds
/// still see the path because the Mach-O loader resolves absolute paths, not
/// PATH entries — but the home prefix has to be read from OpenDirectory
/// (`getpwuid`) instead of `NSHomeDirectory()`, which under sandbox returns
/// the container path (`~/Library/Containers/<bundle-id>/Data`).
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
        let home = realUserHome() ?? NSHomeDirectory()
        var paths = [
            "\(home)/.local/bin/claude",
            "\(home)/Library/Application Support/com.anthropic.claude/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
        ]
        if let nvmPath = nvmBinaryPath(for: "claude", home: home) {
            paths.append(nvmPath)
        }
        return paths
    }

    private static var codexCandidatePaths: [String] {
        let home = realUserHome() ?? NSHomeDirectory()
        var paths = [
            "\(home)/.codex/bin/codex",
            "\(home)/.local/bin/codex",
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
        ]
        if let nvmPath = nvmBinaryPath(for: "codex", home: home) {
            paths.append(nvmPath)
        }
        return paths
    }

    /// Returns `<home>/.nvm/versions/node/<newest>/bin/<binary>` if it exists
    /// and is executable. Walks installed node versions newest-first by parsed
    /// semver (`vMAJOR.MINOR.PATCH`); falls through to older versions when the
    /// newest doesn't have the binary installed (e.g. user just bumped node
    /// but hasn't re-run `npm i -g`). Names that don't parse as semver are
    /// skipped.
    private static func nvmBinaryPath(for binary: String, home: String) -> String? {
        let versionsDir = "\(home)/.nvm/versions/node"
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: versionsDir) else { return nil }
        let sorted = entries
            .compactMap { name -> (name: String, version: (Int, Int, Int))? in
                guard let v = parseSemver(name) else { return nil }
                return (name, v)
            }
            .sorted { $0.version > $1.version }
        for entry in sorted {
            let path = "\(versionsDir)/\(entry.name)/bin/\(binary)"
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func parseSemver(_ name: String) -> (Int, Int, Int)? {
        guard name.hasPrefix("v") else { return nil }
        let parts = name.dropFirst().split(separator: ".")
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2])
        else { return nil }
        return (major, minor, patch)
    }

    /// Resolve the user's REAL home directory, bypassing the sandbox redirect.
    /// `NSHomeDirectory()` returns the container path under App Sandbox; we
    /// need the original `/Users/<name>` so candidate-path lookups for
    /// user-installed CLIs (`~/.local/bin/claude`) succeed. Mirrors the same
    /// helper in `ClaudeCLIAgentRunner`.
    private static func realUserHome() -> String? {
        guard let pw = getpwuid(geteuid()), let dir = pw.pointee.pw_dir else { return nil }
        return String(cString: dir)
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
