import Foundation
import Darwin
import ClearlyCore

enum CLIInstaller {
    static let legacySymlinkPath = "/usr/local/bin/clearly"

    /// The user's *real* home directory. Inside a sandboxed app, both `FileManager.homeDirectoryForCurrentUser`
    /// and `NSHomeDirectory()` return the container path (`~/Library/Containers/<bundle-id>/Data`).
    /// Only `getpwuid(getuid())->pw_dir` bypasses the sandbox remap and returns the real home (`/Users/...`),
    /// which is what the `home-relative-path` entitlement is scoped to.
    static var realHomeDirectoryURL: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    static var primarySymlinkURL: URL {
        realHomeDirectoryURL.appendingPathComponent(".local/bin/clearly", isDirectory: false)
    }

    static var primarySymlinkPath: String { primarySymlinkURL.path }

    static var primaryBinDirectoryURL: URL {
        primarySymlinkURL.deletingLastPathComponent()
    }

    enum State: Equatable {
        case notInstalled
        case installed                          // symlink at ~/.local/bin/clearly points to bundled binary
        case installedLegacy(path: String)      // /usr/local/bin/clearly points to bundled binary (pre-2.5 install)
        case installedElsewhere(URL)            // something named `clearly` exists but points elsewhere
    }

    enum CLIInstallerError: LocalizedError {
        case notBundled
        case wrongOwner(existingTarget: URL?)
        case legacyRequiresManualRemoval(path: String)
        case filesystemError(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .notBundled:
                return "The clearly binary isn't bundled with this build."
            case .wrongOwner:
                return "A different `clearly` is already on your PATH — remove it manually before installing."
            case .legacyRequiresManualRemoval:
                return "This install lives in /usr/local/bin and needs sudo to remove. Copy the command below and run it in Terminal."
            case .filesystemError(let underlying):
                return "Couldn't write the symlink: \(underlying.localizedDescription)"
            }
        }

        var diagnosticPayload: String {
            switch self {
            case .notBundled:
                return "notBundled"
            case .wrongOwner(let existingTarget):
                return "wrongOwner existingTarget=\(existingTarget?.path ?? "<unreadable>")"
            case .legacyRequiresManualRemoval(let path):
                return "legacyRequiresManualRemoval path=\(path)"
            case .filesystemError(let underlying):
                return "filesystemError underlying=\(underlying)"
            }
        }
    }

    static func bundledBinaryURL() -> URL? {
        Bundle.main.url(forResource: "ClearlyCLI", withExtension: nil, subdirectory: "Helpers")
    }

    static func symlinkState() -> State {
        let fm = FileManager.default
        guard let bundled = bundledBinaryURL() else {
            if fm.fileExists(atPath: primarySymlinkPath) {
                return .installedElsewhere(primarySymlinkURL)
            }
            if fm.fileExists(atPath: legacySymlinkPath) {
                return .installedElsewhere(URL(fileURLWithPath: legacySymlinkPath))
            }
            return .notInstalled
        }
        let bundledResolved = bundled.resolvingSymlinksInPath().path

        if let primary = resolvedSymlinkTarget(at: primarySymlinkPath) {
            if primary.path == bundledResolved {
                return .installed
            }
            if fm.fileExists(atPath: primary.path) {
                return .installedElsewhere(primarySymlinkURL)
            }
            // Dangling symlink from a previous Clearly install (e.g. stale DerivedData path).
            // Treat as not installed so the user can reinstall over it.
        } else if fm.fileExists(atPath: primarySymlinkPath) {
            // A non-symlink file is squatting on our target path — treat as foreign.
            return .installedElsewhere(primarySymlinkURL)
        }

        if let legacy = resolvedSymlinkTarget(at: legacySymlinkPath) {
            if legacy.path == bundledResolved {
                return .installedLegacy(path: legacySymlinkPath)
            }
            if fm.fileExists(atPath: legacy.path) {
                return .installedElsewhere(URL(fileURLWithPath: legacySymlinkPath))
            }
            // Dangling legacy symlink — pretend it isn't there.
        } else if fm.fileExists(atPath: legacySymlinkPath) {
            return .installedElsewhere(URL(fileURLWithPath: legacySymlinkPath))
        }

        return .notInstalled
    }

    private static func resolvedSymlinkTarget(at path: String) -> URL? {
        let fm = FileManager.default
        guard let destination = try? fm.destinationOfSymbolicLink(atPath: path) else {
            return nil
        }
        let targetURL: URL
        if destination.hasPrefix("/") {
            targetURL = URL(fileURLWithPath: destination, isDirectory: false)
        } else {
            let parent = (path as NSString).deletingLastPathComponent
            targetURL = URL(fileURLWithPath: parent).appendingPathComponent(destination)
        }
        return targetURL.resolvingSymlinksInPath()
    }

    /// One-liner a user can copy and run themselves. No sudo — writes into `$HOME/.local/bin`.
    /// Returns nil when the helper binary isn't bundled with this build.
    static var shellCommand: String? {
        guard let source = bundledBinaryURL() else { return nil }
        return
            "mkdir -p \"$HOME/.local/bin\" && " +
            "ln -sf '\(shellEscape(source.path))' \"$HOME/.local/bin/clearly\""
    }

    /// Copy-paste command shown when uninstalling a legacy `/usr/local/bin/clearly` symlink.
    static var legacyUninstallCommand: String {
        "sudo rm '\(legacySymlinkPath)'"
    }

    /// The export line users add to their shell profile when `~/.local/bin` isn't on `PATH`.
    static let pathExportLine = #"export PATH="$HOME/.local/bin:$PATH""#

    /// Ordered key/value pairs describing the current install environment.
    /// Surfaced in the Settings "Details" disclosure and copied into bug reports.
    static var diagnosticContext: [(String, String)] {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let bundleId = info?["CFBundleIdentifier"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osString = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        return [
            ("app", "\(version) (\(build))"),
            ("bundleId", bundleId),
            ("macOS", osString),
            ("primaryTarget", primarySymlinkPath),
            ("legacyTarget", legacySymlinkPath),
            ("bundledBinary", bundledBinaryURL()?.path ?? "<missing>"),
        ]
    }

    static func install() async throws {
        DiagnosticLog.log("[cli-install] install requested")
        guard let source = bundledBinaryURL() else {
            DiagnosticLog.log("[cli-install] install failed: notBundled")
            throw CLIInstallerError.notBundled
        }
        if case .installedElsewhere(let url) = symlinkState() {
            DiagnosticLog.log("[cli-install] install aborted: wrongOwner existingTarget=\(url.path)")
            throw CLIInstallerError.wrongOwner(existingTarget: url)
        }

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: primaryBinDirectoryURL, withIntermediateDirectories: true)
            // Remove an existing matching symlink so createSymbolicLink doesn't error.
            if (try? fm.destinationOfSymbolicLink(atPath: primarySymlinkPath)) != nil {
                try fm.removeItem(at: primarySymlinkURL)
            }
            try fm.createSymbolicLink(at: primarySymlinkURL, withDestinationURL: source)
            DiagnosticLog.log("[cli-install] install succeeded: \(primarySymlinkPath) -> \(source.path)")
        } catch {
            DiagnosticLog.log("[cli-install] install failed: filesystemError underlying=\(error)")
            throw CLIInstallerError.filesystemError(underlying: error)
        }
    }

    static func uninstall() async throws {
        DiagnosticLog.log("[cli-install] uninstall requested")
        let state = symlinkState()
        switch state {
        case .installed:
            do {
                try FileManager.default.removeItem(at: primarySymlinkURL)
                DiagnosticLog.log("[cli-install] uninstall succeeded: removed \(primarySymlinkPath)")
            } catch {
                DiagnosticLog.log("[cli-install] uninstall failed: filesystemError underlying=\(error)")
                throw CLIInstallerError.filesystemError(underlying: error)
            }
        case .installedLegacy(let path):
            DiagnosticLog.log("[cli-install] uninstall requires manual sudo: \(path)")
            throw CLIInstallerError.legacyRequiresManualRemoval(path: path)
        case .notInstalled, .installedElsewhere:
            DiagnosticLog.log("[cli-install] uninstall aborted: not our symlink")
            throw CLIInstallerError.wrongOwner(existingTarget: nil)
        }
    }

    /// Best-effort check for whether `~/.local/bin` is on the shell PATH. Scans common rc files
    /// plus the current process environment. False negatives are harmless — they just surface an
    /// extra (safe) "Add to PATH" instruction.
    static func localBinIsOnPath() -> Bool {
        let home = realHomeDirectoryURL.path
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for component in envPath.split(separator: ":") {
            if component == "\(home)/.local/bin" { return true }
        }
        let needleVariants = [
            "\(home)/.local/bin",
            "$HOME/.local/bin",
            "~/.local/bin",
            "${HOME}/.local/bin",
        ]
        let rcFiles = [".zprofile", ".zshrc", ".bash_profile", ".bashrc", ".profile"]
        for name in rcFiles {
            let url = realHomeDirectoryURL.appendingPathComponent(name)
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for needle in needleVariants where contents.contains(needle) {
                return true
            }
        }
        return false
    }

    private static func shellEscape(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\\''")
    }
}
