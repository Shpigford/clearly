import Foundation
import ClearlyCore
import ArgumentParser

enum Emitter {
    /// Emit a single Encodable value. JSON mode uses snake_case keys + sorted
    /// keys to match the MCP structured output contract. Newline-terminated.
    static func emit<T: Encodable>(_ value: T, format: OutputFormat) throws {
        switch format {
        case .json:
            let data = try jsonEncoder().encode(value)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        case .text:
            throw CLIError.textFormatUnavailable
        }
    }

    /// Emit a pre-rendered text line to stdout with a trailing newline.
    static func emitLine(_ line: String) {
        FileHandle.standardOutput.write(Data(line.utf8))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    /// Emit an NDJSON record: one JSON object per line, flushed immediately.
    /// Matches RESEARCH.md §5.6 pipeline contract for list-shaped commands.
    static func emitNDJSONRecord<T: Encodable>(_ value: T) throws {
        let data = try jsonEncoder().encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    static func emitError(_ error: String, message: String, extra: [String: Any] = [:]) {
        var payload: [String: Any] = ["error": error, "message": message]
        for (k, v) in extra { payload[k] = v }
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        FileHandle.standardError.write(data)
        FileHandle.standardError.write(Data("\n".utf8))
    }

    /// Write the structured JSON error for a ToolError to stderr and return
    /// the CLI exit code. Every command's catch block calls this.
    @discardableResult
    static func emitToolError(_ error: ToolError) -> Int32 {
        let (code, data) = error.renderStructured()
        FileHandle.standardError.write(data)
        FileHandle.standardError.write(Data("\n".utf8))
        return code
    }

    private static func jsonEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

enum CLIError: Error {
    case textFormatUnavailable
}

func readAllStdin() -> String {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}

