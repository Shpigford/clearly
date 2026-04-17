import Foundation
import MCP

enum Handlers {
    static func dispatch(params: CallTool.Parameters, vaults: [LoadedVault]) async -> CallTool.Result {
        let multiVault = vaults.count > 1
        do {
            switch params.name {
            case "search_notes":
                let args = SearchNotesArgs(
                    query: params.arguments?["query"]?.stringValue ?? "",
                    limit: params.arguments?["limit"]?.intValue
                )
                let result = try await searchNotes(args, vaults: vaults)
                return .init(content: [.text(renderSearchText(result, multiVault: multiVault))])

            case "get_backlinks":
                let args = GetBacklinksArgs(
                    notePath: params.arguments?["note_path"]?.stringValue ?? ""
                )
                let result = try await getBacklinks(args, vaults: vaults)
                return .init(content: [.text(renderBacklinksText(result, multiVault: multiVault))])

            case "get_tags":
                let args = GetTagsArgs(tag: params.arguments?["tag"]?.stringValue)
                let result = try await getTags(args, vaults: vaults)
                return .init(content: [.text(renderTagsText(result, multiVault: multiVault))])

            case "read_note":
                let args = ReadNoteArgs(
                    relativePath: params.arguments?["relative_path"]?.stringValue ?? "",
                    startLine: params.arguments?["start_line"]?.intValue,
                    endLine: params.arguments?["end_line"]?.intValue,
                    vault: params.arguments?["vault"]?.stringValue
                )
                return await structuredCall { try await readNote(args, vaults: vaults) }

            case "list_notes":
                let args = ListNotesArgs(
                    under: params.arguments?["under"]?.stringValue,
                    vault: params.arguments?["vault"]?.stringValue
                )
                return await structuredCall { try await listNotes(args, vaults: vaults) }

            case "get_headings":
                let args = GetHeadingsArgs(
                    relativePath: params.arguments?["relative_path"]?.stringValue ?? "",
                    vault: params.arguments?["vault"]?.stringValue
                )
                return await structuredCall { try await getHeadings(args, vaults: vaults) }

            case "get_frontmatter":
                let args = GetFrontmatterArgs(
                    relativePath: params.arguments?["relative_path"]?.stringValue ?? "",
                    vault: params.arguments?["vault"]?.stringValue
                )
                return await structuredCall { try await getFrontmatter(args, vaults: vaults) }


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
                return .init(content: [.text("Unknown tool: \(params.name)")], isError: false)
            }
        } catch let error as ToolError {
            // Legacy text-only path — covers the Phase-1 tools (search_notes,
            // get_backlinks, get_tags). Phase 4 ports them to structured output.
            return .init(content: [.text(error.localizedDescription)], isError: true)
        } catch {
            return .init(content: [.text("Error: \(error.localizedDescription)")], isError: true)
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

private func renderSearchText(_ r: SearchNotesResult, multiVault: Bool) -> String {
    if r.totalCount == 0 {
        return "No results found for: \(r.query)"
    }
    var output = "Found \(r.totalCount) file(s) matching \"\(r.query)\""
    if r.totalCount > r.returnedCount {
        output += " (showing first \(r.returnedCount))"
    }
    output += "\n"
    for match in r.results {
        let matchType = match.matchesFilename ? " (filename match)" : ""
        let fullPath = multiVault ? "\(match.vaultPath)/\(match.path)" : match.path
        output += "\n## \(fullPath)\(matchType)\n"
        for excerpt in match.excerpts {
            output += "- Line \(excerpt.lineNumber): \(excerpt.contextLine)\n"
        }
    }
    return output
}

private func renderBacklinksText(_ r: GetBacklinksResult, multiVault: Bool) -> String {
    let displayPath = multiVault ? "\(r.vaultPath)/\(r.notePath)" : r.notePath
    var output = "# Backlinks for: \(displayPath)\n"

    output += "\n## Linked Mentions (\(r.linked.count))\n"
    if r.linked.isEmpty {
        output += "No notes link to this file via [[wiki-links]].\n"
    } else {
        for link in r.linked {
            let line = link.lineNumber.map { " (line \($0))" } ?? ""
            output += "- \(link.source)\(line)\n"
        }
    }

    output += "\n## Unlinked Mentions (\(r.unlinked.count))\n"
    if r.unlinked.isEmpty {
        output += "No unlinked text mentions found.\n"
    } else {
        for mention in r.unlinked {
            output += "- \(mention.path) (line \(mention.lineNumber)): \(mention.contextLine)\n"
        }
    }
    return output
}

private func renderTagsText(_ r: GetTagsResult, multiVault: Bool) -> String {
    switch r.mode {
    case .byTag:
        let tag = r.tag ?? ""
        let files = r.files ?? []
        if files.isEmpty {
            return "No files found with tag #\(tag)"
        }
        var output = "## Files tagged #\(tag) (\(files.count) file(s))\n"
        for f in files {
            let path = multiVault ? "\(f.vaultPath)/\(f.path)" : f.path
            output += "- \(path)\n"
        }
        return output
    case .all:
        let allTags = r.allTags ?? []
        if allTags.isEmpty {
            return "No tags found in the vault."
        }
        var output = "## All Tags (\(allTags.count) tag(s))\n"
        for t in allTags {
            output += "- #\(t.tag) (\(t.count) file(s))\n"
        }
        return output
    }
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
