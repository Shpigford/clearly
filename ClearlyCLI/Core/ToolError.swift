import Foundation

enum ToolError: Error, LocalizedError {
    case missingArgument(String)
    case invalidArgument(name: String, reason: String)
    case noteNotFound(String)

    var errorDescription: String? {
        switch self {
        case .missingArgument(let name):
            return "'\(name)' parameter is required"
        case .invalidArgument(let name, let reason):
            return "'\(name)' \(reason)"
        case .noteNotFound(let path):
            return "Note not found: \(path)\nMake sure the note exists and has been indexed by Clearly."
        }
    }
}
