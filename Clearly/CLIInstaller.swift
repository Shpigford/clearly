import Foundation

enum CLIInstaller {
    static let symlinkPath = "/usr/local/bin/clearly"

    enum State: Equatable {
        case notInstalled
        case installed
        case installedElsewhere(URL)
    }

    enum CLIInstallerError: LocalizedError {
        case notBundled
        case cancelled
        case scriptFailed(code: Int, message: String)
        case wrongOwner

        var errorDescription: String? {
            switch self {
            case .notBundled:
                return "The clearly binary isn't bundled with this build."
            case .cancelled:
                return "Installation was cancelled."
            case .scriptFailed(let code, let message):
                return "Install script failed (code \(code)): \(message)"
            case .wrongOwner:
                return "/usr/local/bin/clearly points at a different tool — remove it manually first."
            }
        }
    }

    static func bundledBinaryURL() -> URL? {
        Bundle.main.url(forResource: "ClearlyCLI", withExtension: nil, subdirectory: "Helpers")
    }

    static func symlinkState() -> State {
        let fm = FileManager.default
        guard let bundled = bundledBinaryURL() else {
            if fm.fileExists(atPath: symlinkPath) {
                return .installedElsewhere(URL(fileURLWithPath: symlinkPath))
            }
            return .notInstalled
        }
        let bundledResolved = bundled.resolvingSymlinksInPath().path

        do {
            let target = try fm.destinationOfSymbolicLink(atPath: symlinkPath)
            let targetURL: URL
            if target.hasPrefix("/") {
                targetURL = URL(fileURLWithPath: target, isDirectory: false)
            } else {
                let parent = (symlinkPath as NSString).deletingLastPathComponent
                targetURL = URL(fileURLWithPath: parent).appendingPathComponent(target)
            }
            let targetResolved = targetURL.resolvingSymlinksInPath().path
            if targetResolved == bundledResolved {
                return .installed
            }
            return .installedElsewhere(URL(fileURLWithPath: symlinkPath))
        } catch {
            if fm.fileExists(atPath: symlinkPath) {
                return .installedElsewhere(URL(fileURLWithPath: symlinkPath))
            }
            return .notInstalled
        }
    }

    static func install() async throws {
        guard let source = bundledBinaryURL() else {
            throw CLIInstallerError.notBundled
        }
        if case .installedElsewhere = symlinkState() {
            throw CLIInstallerError.wrongOwner
        }
        let sourcePath = source.path
        try await runPrivileged(
            shellCommand: "mkdir -p /usr/local/bin && ln -sf '\(escape(sourcePath))' '\(symlinkPath)'"
        )
    }

    static func uninstall() async throws {
        guard symlinkState() == .installed else {
            throw CLIInstallerError.wrongOwner
        }
        try await runPrivileged(shellCommand: "rm -f '\(symlinkPath)'")
    }

    private static func runPrivileged(shellCommand: String) async throws {
        let script = "do shell script \"\(shellCommand.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        try await Task.detached(priority: .userInitiated) {
            var errorDict: NSDictionary?
            guard let apple = NSAppleScript(source: script) else {
                throw CLIInstallerError.scriptFailed(code: -1, message: "Could not compile AppleScript")
            }
            _ = apple.executeAndReturnError(&errorDict)
            if let err = errorDict {
                let code = (err["NSAppleScriptErrorNumber"] as? Int) ?? 0
                if code == -128 {
                    throw CLIInstallerError.cancelled
                }
                let msg = (err["NSAppleScriptErrorMessage"] as? String) ?? "Unknown error"
                throw CLIInstallerError.scriptFailed(code: code, message: msg)
            }
        }.value
    }

    private static func escape(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\\''")
    }
}
