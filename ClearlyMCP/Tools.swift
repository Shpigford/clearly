import Foundation
import MCP

// MARK: - MCP Server Setup

func startMCPServer(indexes: [(index: VaultIndex, url: URL)]) async throws {
    let vaultPaths = indexes.map { $0.url.path }
    let vaultDescription = vaultPaths.joined(separator: ", ")

    let server = Server(
        name: "clearly",
        version: "1.0.0",
        capabilities: .init(tools: .init(listChanged: false))
    )

    await server.withMethodHandler(ListTools.self) { _ in
        .init(tools: [
            Tool(
                name: "search_notes",
                description: "Full-text search across all notes in Clearly. Searches \(indexes.count) vault(s): \(vaultDescription). Returns relevance-ranked results with context snippets. Uses BM25 ranking and stemming. Results include the vault path and relative file path — use standard file access to read full content.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object([
                            "type": .string("string"),
                            "description": .string("Search query. Supports quoted phrases for exact match.")
                        ]),
                        "limit": .object([
                            "type": .string("integer"),
                            "description": .string("Max results to return (default 20)")
                        ])
                    ]),
                    "required": .array([.string("query")])
                ])
            ),
            Tool(
                name: "get_backlinks",
                description: "Get all notes that link to a given note via [[wiki-links]], plus unlinked text mentions (places the note is referenced by name but not yet linked). Searches across all vaults.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "note_path": .object([
                            "type": .string("string"),
                            "description": .string("Note filename (e.g. 'My Note') or relative path within a vault (e.g. 'folder/My Note.md')")
                        ])
                    ]),
                    "required": .array([.string("note_path")])
                ])
            ),
            Tool(
                name: "get_tags",
                description: "Without arguments: list all tags across all vaults with file counts. With a tag argument: list all files with that tag. Tags come from both inline #hashtags and YAML frontmatter.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "tag": .object([
                            "type": .string("string"),
                            "description": .string("Specific tag to look up (without # prefix). Omit to list all tags.")
                        ])
                    ])
                ])
            )
        ])
    }

    await server.withMethodHandler(CallTool.self) { params in
        switch params.name {
        case "search_notes":
            return handleSearchNotes(params: params, indexes: indexes)
        case "get_backlinks":
            return handleGetBacklinks(params: params, indexes: indexes)
        case "get_tags":
            return handleGetTags(params: params, indexes: indexes)
        default:
            return .init(content: [.text("Unknown tool: \(params.name)")], isError: false)
        }
    }

    let transport = StdioTransport()
    try await server.start(transport: transport)

    // Block until the process is terminated
    try await Task.sleep(for: .seconds(365 * 24 * 3600))
}

// MARK: - Tool Handlers

private func handleSearchNotes(params: CallTool.Parameters, indexes: [(index: VaultIndex, url: URL)]) -> CallTool.Result {
    guard let query = params.arguments?["query"]?.stringValue, !query.isEmpty else {
        return .init(content: [.text("Error: 'query' parameter is required")], isError: true)
    }

    let rawLimit = params.arguments?["limit"]?.intValue
    if let rawLimit, rawLimit <= 0 {
        return .init(content: [.text("Error: 'limit' must be greater than 0")], isError: true)
    }
    let limit = min(rawLimit ?? 20, 100)

    // Search across all vaults, collect results with vault context
    var allResults: [(vaultPath: String, group: SearchFileGroup)] = []
    for (index, url) in indexes {
        let results = index.searchFilesGrouped(query: query)
        for group in results {
            allResults.append((url.path, group))
        }
    }

    allResults.sort(by: isHigherPrioritySearchResult)

    if allResults.isEmpty {
        return .init(content: [.text("No results found for: \(query)")])
    }

    let capped = Array(allResults.prefix(limit))
    var output = "Found \(allResults.count) file(s) matching \"\(query)\""
    if allResults.count > limit {
        output += " (showing first \(limit))"
    }
    output += "\n"

    let multiVault = indexes.count > 1
    for result in capped {
        let matchType = result.group.matchesFilename ? " (filename match)" : ""
        let fullPath = multiVault ? "\(result.vaultPath)/\(result.group.file.path)" : result.group.file.path
        output += "\n## \(fullPath)\(matchType)\n"
        for excerpt in result.group.excerpts {
            output += "- Line \(excerpt.lineNumber): \(excerpt.contextLine)\n"
        }
    }

    return .init(content: [.text(output)])
}

private func isHigherPrioritySearchResult(
    _ lhs: (vaultPath: String, group: SearchFileGroup),
    _ rhs: (vaultPath: String, group: SearchFileGroup)
) -> Bool {
    if lhs.group.matchesFilename != rhs.group.matchesFilename {
        return lhs.group.matchesFilename
    }
    if lhs.group.relevanceRank != rhs.group.relevanceRank {
        return lhs.group.relevanceRank < rhs.group.relevanceRank
    }
    if lhs.vaultPath != rhs.vaultPath {
        return lhs.vaultPath.localizedCaseInsensitiveCompare(rhs.vaultPath) == .orderedAscending
    }
    return lhs.group.file.path.localizedCaseInsensitiveCompare(rhs.group.file.path) == .orderedAscending
}

private func handleGetBacklinks(params: CallTool.Parameters, indexes: [(index: VaultIndex, url: URL)]) -> CallTool.Result {
    guard let notePath = params.arguments?["note_path"]?.stringValue, !notePath.isEmpty else {
        return .init(content: [.text("Error: 'note_path' parameter is required")], isError: true)
    }

    // Try to resolve in each vault
    for (index, url) in indexes {
        let file: IndexedFile?
        if let f = index.file(forRelativePath: notePath) {
            file = f
        } else if let f = index.resolveWikiLink(name: notePath) {
            file = f
        } else {
            let withoutExt = notePath.hasSuffix(".md") ? String(notePath.dropLast(3)) : notePath
            file = index.resolveWikiLink(name: withoutExt)
        }

        guard let file = file else { continue }

        let linked = index.linksTo(fileId: file.id)
        let unlinked = index.unlinkedMentions(for: file.filename, excludingFileId: file.id)

        let multiVault = indexes.count > 1
        let displayPath = multiVault ? "\(url.path)/\(file.path)" : file.path
        var output = "# Backlinks for: \(displayPath)\n"

        output += "\n## Linked Mentions (\(linked.count))\n"
        if linked.isEmpty {
            output += "No notes link to this file via [[wiki-links]].\n"
        } else {
            for link in linked {
                let source = link.sourcePath ?? link.sourceFilename ?? "unknown"
                let line = link.lineNumber.map { " (line \($0))" } ?? ""
                output += "- \(source)\(line)\n"
            }
        }

        output += "\n## Unlinked Mentions (\(unlinked.count))\n"
        if unlinked.isEmpty {
            output += "No unlinked text mentions found.\n"
        } else {
            for mention in unlinked {
                output += "- \(mention.file.path) (line \(mention.lineNumber)): \(mention.contextLine)\n"
            }
        }

        return .init(content: [.text(output)])
    }

    return .init(content: [.text("Note not found: \(notePath)\nMake sure the note exists and has been indexed by Clearly.")], isError: true)
}

private func handleGetTags(params: CallTool.Parameters, indexes: [(index: VaultIndex, url: URL)]) -> CallTool.Result {
    let tag = params.arguments?["tag"]?.stringValue
    let multiVault = indexes.count > 1

    if let tag = tag, !tag.isEmpty {
        var allFiles: [(vaultPath: String, file: IndexedFile)] = []
        for (index, url) in indexes {
            for file in index.filesForTag(tag: tag) {
                allFiles.append((url.path, file))
            }
        }
        if allFiles.isEmpty {
            return .init(content: [.text("No files found with tag #\(tag)")])
        }
        var output = "## Files tagged #\(tag) (\(allFiles.count) file(s))\n"
        for (vaultPath, file) in allFiles {
            let path = multiVault ? "\(vaultPath)/\(file.path)" : file.path
            output += "- \(path)\n"
        }
        return .init(content: [.text(output)])
    } else {
        // Aggregate tags across all vaults
        var tagCounts: [String: Int] = [:]
        for (index, _) in indexes {
            for (tag, count) in index.allTags() {
                tagCounts[tag, default: 0] += count
            }
        }
        if tagCounts.isEmpty {
            return .init(content: [.text("No tags found in the vault.")])
        }
        let sorted = tagCounts.sorted { $0.key < $1.key }
        var output = "## All Tags (\(sorted.count) tag(s))\n"
        for (tag, count) in sorted {
            output += "- #\(tag) (\(count) file(s))\n"
        }
        return .init(content: [.text(output)])
    }
}

// MARK: - Value Extensions

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
