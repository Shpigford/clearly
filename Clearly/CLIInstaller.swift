import Foundation
import ClearlyCore

enum CLIInstaller {
    static let symlinkPath = "/usr/local/bin/clearly"

    enum State: Equatable {
        case notInstalled
        case installed
        case installedElsewhere(URL)
    }

    enum CLIInstallerError: LocalizedError {
        case notBundled
        case wrongOwner(existingTarget: URL?)
        case appleScriptCompileFailed
        case terminalAutomationDenied(code: Int, message: String)
        case scriptFailed(code: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .notBundled:
                return "The clearly binary isn't bundled with this build."
            case .wrongOwner:
                return "/usr/local/bin/clearly points at a different tool — remove it manually first."
            case .appleScriptCompileFailed:
                return "Couldn't build the install command — please report this."
            case .terminalAutomationDenied:
                return "Clearly doesn't have permission to control Terminal. Open Privacy & Security → Automation and allow Clearly, or copy the command and run it yourself."
            case .scriptFailed(let code, let message):
                return "Terminal returned an error (code \(code)): \(message)"
            }
        }

        var diagnosticPayload: String {
            switch self {
            case .notBundled:
                return "notBundled"
            case .wrongOwner(let existingTarget):
                return "wrongOwner existingTarget=\(existingTarget?.path ?? "<unreadable>")"
            case .appleScriptCompileFailed:
                return "appleScriptCompileFailed"
            case .terminalAutomationDenied(let code, let message):
                return "terminalAutomationDenied code=\(code) message=\(message)"
            case .scriptFailed(let code, let message):
                return "scriptFailed code=\(code) message=\(message)"
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

    /// The exact one-liner a user can copy and run in Terminal themselves.
    /// Returns nil when the helper binary isn't bundled with this build.
    static var shellCommand: String? {
        guard let source = bundledBinaryURL() else { return nil }
        return
            "sudo mkdir -p /usr/local/bin && " +
            "sudo ln -sf '\(shellEscape(source.path))' '\(symlinkPath)'"
    }

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
            ("symlinkTarget", symlinkPath),
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
        let scriptCommand =
            "sudo mkdir -p /usr/local/bin && " +
            "sudo ln -sf '\(shellEscape(source.path))' '\(symlinkPath)' && " +
            "echo '' && " +
            "echo '✓ Installed. You can close this window — clearly is on your PATH.'"
        do {
            try await runInTerminal(scriptCommand)
            DiagnosticLog.log("[cli-install] install dispatched to Terminal")
        } catch let error as CLIInstallerError {
            DiagnosticLog.log("[cli-install] install failed: \(error.diagnosticPayload)")
            throw error
        }
    }

    static func uninstall() async throws {
        DiagnosticLog.log("[cli-install] uninstall requested")
        guard symlinkState() == .installed else {
            DiagnosticLog.log("[cli-install] uninstall aborted: wrongOwner")
            throw CLIInstallerError.wrongOwner(existingTarget: URL(fileURLWithPath: symlinkPath))
        }
        let scriptCommand =
            "sudo rm -f '\(symlinkPath)' && " +
            "echo '' && " +
            "echo '✓ Uninstalled. You can close this window.'"
        do {
            try await runInTerminal(scriptCommand)
            DiagnosticLog.log("[cli-install] uninstall dispatched to Terminal")
        } catch let error as CLIInstallerError {
            DiagnosticLog.log("[cli-install] uninstall failed: \(error.diagnosticPayload)")
            throw error
        }
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
                throw CLIInstallerError.appleScriptCompileFailed
            }
            _ = apple.executeAndReturnError(&errorDict)
            if let err = errorDict {
                let code = (err["NSAppleScriptErrorNumber"] as? Int) ?? 0
                let msg = (err["NSAppleScriptErrorMessage"] as? String) ?? "Unknown error"
                if code == -1743 || code == -600 {
                    throw CLIInstallerError.terminalAutomationDenied(code: code, message: msg)
                }
                throw CLIInstallerError.scriptFailed(code: code, message: msg)
            }
        }.value
    }

    private static func shellEscape(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\\''")
    }
}
