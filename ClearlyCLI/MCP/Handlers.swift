import Foundation
import MCP

enum Handlers {
    static func dispatch(params: CallTool.Parameters, vaults: [LoadedVault]) async -> CallTool.Result {
        switch params.name {
        case "search_notes":
            return await structuredCall {
                let args = SearchNotesArgs(
                    query: params.arguments?["query"]?.stringValue ?? "",
                    limit: params.arguments?["limit"]?.intValue
                )
                return try await searchNotes(args, vaults: vaults)
            }

        case "get_backlinks":
            return await structuredCall {
                let args = GetBacklinksArgs(
                    relativePath: params.arguments?["relative_path"]?.stringValue ?? "",
                    vault: params.arguments?["vault"]?.stringValue
                )
                return try await getBacklinks(args, vaults: vaults)
            }

        case "get_tags":
            return await structuredCall {
                let args = GetTagsArgs(tag: params.arguments?["tag"]?.stringValue)
                return try await getTags(args, vaults: vaults)
            }

        case "read_note":
            return await structuredCall {
                let args = ReadNoteArgs(
                    relativePath: params.arguments?["relative_path"]?.stringValue ?? "",
                    startLine: params.arguments?["start_line"]?.intValue,
                    endLine: params.arguments?["end_line"]?.intValue,
                    vault: params.arguments?["vault"]?.stringValue
                )
                return try await readNote(args, vaults: vaults)
            }

        case "list_notes":
            return await structuredCall {
                let args = ListNotesArgs(
                    under: params.arguments?["under"]?.stringValue,
                    vault: params.arguments?["vault"]?.stringValue
                )
                return try await listNotes(args, vaults: vaults)
            }

        case "get_headings":
            return await structuredCall {
                let args = GetHeadingsArgs(
                    relativePath: params.arguments?["relative_path"]?.stringValue ?? "",
                    vault: params.arguments?["vault"]?.stringValue
                )
                return try await getHeadings(args, vaults: vaults)
            }

        case "get_frontmatter":
            return await structuredCall {
                let args = GetFrontmatterArgs(
                    relativePath: params.arguments?["relative_path"]?.stringValue ?? "",
                    vault: params.arguments?["vault"]?.stringValue
                )
                return try await getFrontmatter(args, vaults: vaults)
            }

        case "create_note":
            return await structuredCall {
                let args = CreateNoteArgs(
                    relativePath: params.arguments?["relative_path"]?.stringValue ?? "",
                    content: params.arguments?["content"]?.stringValue ?? "",
                    vault: params.arguments?["vault"]?.stringValue
                )
                return try await createNote(args, vaults: vaults)
            }

        case "update_note":
            return await structuredCall {
                guard let modeStr = params.arguments?["mode"]?.stringValue,
                      let mode = UpdateMode(rawValue: modeStr) else {
                    throw ToolError.invalidArgument(name: "mode", reason: "must be one of: replace, append, prepend")
                }
                let args = UpdateNoteArgs(
                    relativePath: params.arguments?["relative_path"]?.stringValue ?? "",
                    content: params.arguments?["content"]?.stringValue ?? "",
                    mode: mode,
                    vault: params.arguments?["vault"]?.stringValue
                )
                return try await updateNote(args, vaults: vaults)
            }

        default:
            return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
        }
    }

    /// Run a new structured-output tool and return a CallTool.Result with both
    /// `content: [.text(json)]` (for older clients) and `structuredContent`
    /// (for clients following the 2025-11-25 MCP spec).
    /// Errors are rendered as structured JSON with `isError: true` so the shape
    /// is stable across the success and error paths.
    private static func structuredCall<T: Encodable>(
        _ work: () async throws -> T
    ) async -> CallTool.Result {
        do {
            let value = try await work()
            let (text, structured) = try encodeStructured(value)
            let boxed: Value? = structured
            return .init(content: [.text(text)], structuredContent: boxed, isError: false)
        } catch let error as ToolError {
            let (_, data) = error.renderStructured()
            let text = String(data: data, encoding: .utf8) ?? "{}"
            let structured: Value? = (try? JSONDecoder().decode(Value.self, from: data)) ?? .object([:])
            return .init(content: [.text(text)], structuredContent: structured, isError: true)
        } catch {
            let payload: [String: Any] = [
                "error": "internal_error",
                "message": error.localizedDescription
            ]
            let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data("{}".utf8)
            let text = String(data: data, encoding: .utf8) ?? "{}"
            let structured: Value? = (try? JSONDecoder().decode(Value.self, from: data)) ?? .object([:])
            return .init(content: [.text(text)], structuredContent: structured, isError: true)
        }
    }
}

/// Encode an `Encodable` value to both a JSON string (for `content: [.text]`)
/// and a `Value` (for `structuredContent`). Snake_case keys on output.
func encodeStructured<T: Encodable>(_ value: T) throws -> (text: String, structured: Value) {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    let text = String(data: data, encoding: .utf8) ?? "{}"
    let structured = try JSONDecoder().decode(Value.self, from: data)
    return (text, structured)
}

private extension Value {
    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    var intValue: Int? {
        if case .int(let n) = self { return n }
        if case .double(let d) = self { return Int(d) }
        return nil
    }
}
