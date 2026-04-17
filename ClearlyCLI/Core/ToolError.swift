import Foundation

enum ToolError: Error, LocalizedError {
    case missingArgument(String)
    case invalidArgument(name: String, reason: String)
    case noteNotFound(String)

    // Exact text the MCP adapter emits in the `.text` content block. Preserves
    // byte-for-byte parity with the pre-refactor handler output — notably,
    // .noteNotFound has NO "Error: " prefix.
    var errorDescription: String? {
        switch self {
        case .missingArgument(let name):
            return "Error: '\(name)' parameter is required"
        case .invalidArgument(let name, let reason):
            return "Error: '\(name)' \(reason)"
        case .noteNotFound(let path):
            return "Note not found: \(path)\nMake sure the note exists and has been indexed by Clearly."
        }
    }
}
