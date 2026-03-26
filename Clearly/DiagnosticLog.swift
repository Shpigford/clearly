import Foundation
import os
import OSLog

enum DiagnosticLog {
    static let logger = Logger(subsystem: "com.sabotage.clearly", category: "lifecycle")

    static func exportRecentLogs() throws -> String {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let cutoff = store.position(date: Date().addingTimeInterval(-30 * 60))
        let entries = try store.getEntries(at: cutoff, matching: NSPredicate(format: "subsystem == %@", "com.sabotage.clearly"))

        var lines: [String] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        for entry in entries {
            guard let logEntry = entry as? OSLogEntryLog else { continue }
            let timestamp = formatter.string(from: logEntry.date)
            lines.append("[\(timestamp)] [\(logEntry.category)] \(logEntry.composedMessage)")
        }

        let info = Bundle.main.infoDictionary
        let appVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = info?["CFBundleVersion"] as? String ?? "?"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let model = Self.hardwareModel()

        var header = "Clearly Diagnostic Log\n"
            + String(repeating: "─", count: 60) + "\n"
            + "Exported:  \(formatter.string(from: Date()))\n"
            + "Clearly:   \(appVersion) (\(buildNumber))\n"
            + "macOS:     \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)\n"
            + "Hardware:  \(model)\n"
            + "Memory:    \(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)) GB\n"
            + "Uptime:    \(Int(ProcessInfo.processInfo.systemUptime / 3600))h \(Int(ProcessInfo.processInfo.systemUptime.truncatingRemainder(dividingBy: 3600) / 60))m\n"
            + String(repeating: "─", count: 60) + "\n\n"

        if lines.isEmpty {
            header += "No diagnostic log entries in the last 30 minutes.\n\nIf the app crashed or was force-quit, try exporting immediately after relaunching."
            return header
        }

        return header + lines.joined(separator: "\n")
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}
