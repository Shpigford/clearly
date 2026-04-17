import Foundation

enum Emitter {
    static func emit<T: Encodable>(_ value: T, format: OutputFormat) throws {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(value)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        case .text:
            // Phase 2 fills in text emitters alongside the read tools that need them.
            throw CLIError.textFormatUnavailable
        }
    }

    static func emitError(_ error: String, message: String, extra: [String: String] = [:]) {
        var payload: [String: String] = ["error": error, "message": message]
        for (k, v) in extra { payload[k] = v }
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        FileHandle.standardError.write(data)
        FileHandle.standardError.write(Data("\n".utf8))
    }
}

enum CLIError: Error {
    case textFormatUnavailable
}
