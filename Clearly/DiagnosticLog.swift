import Foundation
import os

enum DiagnosticLog {
    static let logger = Logger(subsystem: "com.sabotage.clearly", category: "lifecycle")

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let logFileURL: URL? = {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let appDir = dir.appendingPathComponent("Clearly")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("diagnostic.log")
    }()

    private static let fileQueue = DispatchQueue(label: "com.sabotage.clearly.log")

    /// Log to both os_log and a persistent file that survives force-quit
    static func log(_ message: String) {
        logger.info("\(message, privacy: .public)")
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [lifecycle] \(message)\n"
        guard let url = logFileURL, let data = line.data(using: .utf8) else { return }
        fileQueue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: url)
            }
        }
    }

    /// Trim log file if over 1MB, keeping the last ~500KB
    static func trimIfNeeded() {
        guard let url = logFileURL else { return }
        fileQueue.async {
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? UInt64,
                  size > 1_000_000,
                  let content = try? String(contentsOf: url, encoding: .utf8) else { return }
            let idx = content.index(content.endIndex, offsetBy: -500_000, limitedBy: content.startIndex) ?? content.startIndex
            let start = content[idx...].firstIndex(of: "\n").map { content.index(after: $0) } ?? idx
            try? String(content[start...]).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func exportRecentLogs() throws -> String {
        let info = Bundle.main.infoDictionary
        let appVersion = info?["CFBundleShortVersionString"] as? String ?? "?"
        let buildNumber = info?["CFBundleVersion"] as? String ?? "?"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let model = hardwareModel()

        var output = "Clearly Diagnostic Log\n"
            + String(repeating: "─", count: 60) + "\n"
            + "Exported:  \(dateFormatter.string(from: Date()))\n"
            + "Clearly:   \(appVersion) (\(buildNumber))\n"
            + "macOS:     \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)\n"
            + "Hardware:  \(model)\n"
            + "Memory:    \(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)) GB\n"
            + "Uptime:    \(Int(ProcessInfo.processInfo.systemUptime / 3600))h \(Int(ProcessInfo.processInfo.systemUptime.truncatingRemainder(dividingBy: 3600) / 60))m\n"
            + String(repeating: "─", count: 60) + "\n\n"

        // Flush pending writes before reading
        fileQueue.sync {}

        guard let url = logFileURL,
              let content = try? String(contentsOf: url, encoding: .utf8),
              !content.isEmpty else {
            return output + "No log entries available."
        }

        // Include all entries from the file (capped at ~1MB by trimIfNeeded)
        return output + content
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
}
