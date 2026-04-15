import AppKit
import Foundation

enum AppRelauncher {
    static func relaunchIfPossible() {
        let bundlePath = Bundle.main.bundleURL.path.replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; open \"\(bundlePath)\""]
        try? process.run()

        NSApp.terminate(nil)
    }
}
