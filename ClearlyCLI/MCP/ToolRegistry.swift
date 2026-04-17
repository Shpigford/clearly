import Foundation
import MCP

enum ToolRegistry {
    static func listTools(vaults: [LoadedVault]) -> [Tool] {
        let vaultPaths = vaults.map { $0.url.path }
        let vaultDescription = vaultPaths.joined(separator: ", ")

        return [
            Tool(
                name: "search_notes",
                description: "Full-text search across all notes in Clearly. Searches \(vaults.count) vault(s): \(vaultDescription). Returns relevance-ranked results with context snippets. Uses BM25 ranking and stemming. Results include the vault path and relative file path — use standard file access to read full content.",
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
        ]
    }
}
