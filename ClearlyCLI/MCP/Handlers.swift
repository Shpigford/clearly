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

            default:
                return .init(content: [.text("Unknown tool: \(params.name)")], isError: false)
            }
        } catch let error as ToolError {
            return .init(content: [.text(error.localizedDescription)], isError: true)
        } catch {
            return .init(content: [.text("Error: \(error.localizedDescription)")], isError: true)
        }
    }
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
