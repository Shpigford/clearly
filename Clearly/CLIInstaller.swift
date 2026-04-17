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
        case terminalUnavailable
        case scriptFailed(code: Int, message: String)
        case wrongOwner

        var errorDescription: String? {
            switch self {
            case .notBundled:
                return "The clearly binary isn't bundled with this build."
            case .terminalUnavailable:
                return "Couldn't open Terminal. Check Privacy & Security → Automation and allow Clearly to control Terminal."
            case .scriptFailed(let code, let message):
                return "Couldn't open Terminal (code \(code)): \(message)"
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
        let shellCommand =
            "sudo mkdir -p /usr/local/bin && " +
            "sudo ln -sf '\(shellEscape(source.path))' '\(symlinkPath)' && " +
            "echo '' && " +
            "echo '✓ Installed. You can close this window — clearly is on your PATH.'"
        try await runInTerminal(shellCommand)
    }

    static func uninstall() async throws {
        guard symlinkState() == .installed else {
            throw CLIInstallerError.wrongOwner
        }
        let shellCommand =
            "sudo rm -f '\(symlinkPath)' && " +
            "echo '' && " +
            "echo '✓ Uninstalled. You can close this window.'"
        try await runInTerminal(shellCommand)
    }

    private static func runInTerminal(_ shellCommand: String) async throws {
        let escapedForAS = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedForAS)"
        end tell
        """
        try await Task.detached(priority: .userInitiated) {
            var errorDict: NSDictionary?
            guard let apple = NSAppleScript(source: script) else {
                throw CLIInstallerError.scriptFailed(code: -1, message: "Could not compile AppleScript")
            }
            _ = apple.executeAndReturnError(&errorDict)
            if let err = errorDict {
                let code = (err["NSAppleScriptErrorNumber"] as? Int) ?? 0
                let msg = (err["NSAppleScriptErrorMessage"] as? String) ?? "Unknown error"
                if code == -1743 || code == -600 {
                    throw CLIInstallerError.terminalUnavailable
                }
                throw CLIInstallerError.scriptFailed(code: code, message: msg)
            }
        }.value
    }

    private static func shellEscape(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\\''")
    }
}
