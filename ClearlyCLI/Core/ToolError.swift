import Foundation

enum ToolError: Error, LocalizedError {
    case missingArgument(String)
    case invalidArgument(name: String, reason: String)
    case invalidEncoding(String)
    case noteNotFound(String)
    case pathOutsideVault(String)
    case ambiguousVault(relativePath: String, matches: [String])
    case conflict(existingPath: String)

    // Exact text the MCP adapter emits in the `.text` content block. Preserves
    // byte-for-byte parity with the pre-refactor handler output — notably,
    // .noteNotFound has NO "Error: " prefix.
    var errorDescription: String? {
        switch self {
        case .missingArgument(let name):
            return "Error: '\(name)' parameter is required"
        case .invalidArgument(let name, let reason):
            return "Error: '\(name)' \(reason)"
        case .invalidEncoding(let path):
            return "File is not valid UTF-8: \(path)"
        case .noteNotFound(let path):
            return "Note not found: \(path)\nMake sure the note exists and has been indexed by Clearly."
        case .pathOutsideVault(let path):
            return "Path resolves outside the vault: \(path)"
        case .ambiguousVault(let path, let matches):
            return "Ambiguous path '\(path)': matches \(matches.count) vaults (\(matches.joined(separator: ", "))). Specify --vault or the vault field."
        case .conflict(let path):
            return "Note already exists: \(path)\nUse update_note to modify existing notes."
        }
    }
}

extension ToolError {
    /// Maps a ToolError to a CLI exit code and a stable structured JSON payload.
    /// Keys are snake_case to match the broader JSON contract.
    func renderStructured() -> (exitCode: Int32, json: Data) {
        let code: Int32
        var payload: [String: Any] = [:]

        switch self {
        case .missingArgument(let name):
            code = 2
            payload["error"] = "missing_argument"
            payload["message"] = errorDescription ?? ""
            payload["argument"] = name
        case .invalidArgument(let name, let reason):
            code = 2
            payload["error"] = "invalid_argument"
            payload["message"] = errorDescription ?? ""
            payload["argument"] = name
            payload["reason"] = reason
        case .invalidEncoding(let path):
            code = 1
            payload["error"] = "invalid_encoding"
            payload["message"] = errorDescription ?? ""
            payload["relative_path"] = path
        case .noteNotFound(let path):
            code = 3
            payload["error"] = "note_not_found"
            payload["message"] = errorDescription ?? ""
            payload["relative_path"] = path
        case .pathOutsideVault(let path):
            code = 4
            payload["error"] = "path_outside_vault"
            payload["message"] = errorDescription ?? ""
            payload["relative_path"] = path
        case .ambiguousVault(let path, let matches):
            code = 5
            payload["error"] = "ambiguous_path"
            payload["message"] = errorDescription ?? ""
            payload["relative_path"] = path
            payload["matches"] = matches
        case .conflict(let path):
            code = 5
            payload["error"] = "note_exists"
            payload["message"] = errorDescription ?? ""
            payload["relative_path"] = path
        }

        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data("{}".utf8)
        return (code, data)
    }
}
