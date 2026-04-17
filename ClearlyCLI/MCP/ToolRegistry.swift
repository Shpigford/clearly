import Foundation
import MCP

enum ToolRegistry {
    static func listTools(vaults: [LoadedVault]) -> [Tool] {
        let vaultPaths = vaults.map { $0.url.path }
        let vaultDescription = vaultPaths.joined(separator: ", ")

        let readAnnotations = Tool.Annotations(
            readOnlyHint: true,
            destructiveHint: false,
            idempotentHint: true,
            openWorldHint: false
        )

        let writeAnnotations = Tool.Annotations(
            readOnlyHint: false,
            destructiveHint: true,
            idempotentHint: false,
            openWorldHint: false
        )

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
            ),
            Tool(
                name: "read_note",
                description: "Read the full content of a note in a vault, optionally restricted to a line range. Returns content plus metadata (content hash, size, modification time, parsed frontmatter, headings, tags).",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "relative_path": .object([
                            "type": .string("string"),
                            "description": .string("Vault-relative path, e.g. 'Daily/2026-04-16.md'. Must not start with '/' or contain '..'.")
                        ]),
                        "start_line": .object([
                            "type": .string("integer"),
                            "minimum": .int(1),
                            "description": .string("Optional. 1-based line number to start reading from. Omit to read from the beginning.")
                        ]),
                        "end_line": .object([
                            "type": .string("integer"),
                            "minimum": .int(1),
                            "description": .string("Optional. 1-based line number to stop at (inclusive). Omit to read to end of file.")
                        ]),
                        "vault": .object([
                            "type": .string("string"),
                            "description": .string("Optional vault name disambiguator. Required only when multiple vaults are loaded and 'relative_path' is ambiguous.")
                        ])
                    ]),
                    "required": .array([.string("relative_path")])
                ]),
                annotations: readAnnotations,
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "vault":          .object(["type": .string("string")]),
                        "relative_path":  .object(["type": .string("string")]),
                        "content":        .object(["type": .string("string")]),
                        "content_hash":   .object(["type": .string("string")]),
                        "size_bytes":     .object(["type": .string("integer")]),
                        "modified_at":    .object(["type": .string("string"), "format": .string("date-time")]),
                        "frontmatter":    .object(["type": .string("object"), "additionalProperties": .object(["type": .string("string")])]),
                        "headings":       .object(["type": .string("array"), "items": .object(["type": .string("object")])]),
                        "tags":           .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                        "line_range":     .object(["type": .string("object"), "description": .string("Present when start_line / end_line were specified.")])
                    ]),
                    "required": .array([.string("vault"), .string("relative_path"), .string("content"), .string("content_hash")])
                ])
            ),
            Tool(
                name: "list_notes",
                description: "List notes in loaded vault(s). Uses a fresh filesystem walk (always current) rather than the index. Optionally restricted to a subpath prefix.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "under": .object([
                            "type": .string("string"),
                            "description": .string("Optional vault-relative directory prefix, e.g. 'Daily/'. Only notes whose path starts with this prefix are returned.")
                        ]),
                        "vault": .object([
                            "type": .string("string"),
                            "description": .string("Optional vault name. When omitted, notes across all loaded vaults are returned.")
                        ])
                    ])
                ]),
                annotations: readAnnotations,
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "notes": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("object")])
                        ])
                    ]),
                    "required": .array([.string("notes")])
                ])
            ),
            Tool(
                name: "get_headings",
                description: "Return the heading outline (H1–H6) of a note, including heading text, level, and 1-based line number. Sourced from the index.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "relative_path": .object([
                            "type": .string("string"),
                            "description": .string("Vault-relative path, e.g. 'Strategy/pricing.md'.")
                        ]),
                        "vault": .object([
                            "type": .string("string"),
                            "description": .string("Optional vault name disambiguator.")
                        ])
                    ]),
                    "required": .array([.string("relative_path")])
                ]),
                annotations: readAnnotations,
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "vault":         .object(["type": .string("string")]),
                        "relative_path": .object(["type": .string("string")]),
                        "headings":      .object(["type": .string("array"), "items": .object(["type": .string("object")])])
                    ]),
                    "required": .array([.string("vault"), .string("relative_path"), .string("headings")])
                ])
            ),
            Tool(
                name: "get_frontmatter",
                description: "Return the parsed YAML frontmatter of a note as a flat key-value map. Returns an empty map when the note has no frontmatter block.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "relative_path": .object([
                            "type": .string("string"),
                            "description": .string("Vault-relative path, e.g. 'Projects/2026-plan.md'.")
                        ]),
                        "vault": .object([
                            "type": .string("string"),
                            "description": .string("Optional vault name disambiguator.")
                        ])
                    ]),
                    "required": .array([.string("relative_path")])
                ]),
                annotations: readAnnotations,
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "vault":           .object(["type": .string("string")]),
                        "relative_path":   .object(["type": .string("string")]),
                        "frontmatter":     .object(["type": .string("object"), "additionalProperties": .object(["type": .string("string")])]),
                        "has_frontmatter": .object(["type": .string("boolean")])
                    ]),
                    "required": .array([.string("vault"), .string("relative_path"), .string("frontmatter"), .string("has_frontmatter")])
                ])
            ),
            Tool(
                name: "create_note",
                description: "Create a new markdown note at the specified vault-relative path. Parent directories are created automatically. Fails with a conflict error if the note already exists — use update_note to modify existing notes.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "relative_path": .object([
                            "type": .string("string"),
                            "description": .string("Vault-relative path for the new note, e.g. 'Daily/2026-04-17.md'. Must not start with '/' or contain '..'. Parent folders are created automatically.")
                        ]),
                        "content": .object([
                            "type": .string("string"),
                            "description": .string("Full markdown content, including optional YAML frontmatter delimited by '---'.")
                        ]),
                        "vault": .object([
                            "type": .string("string"),
                            "description": .string("Optional. Name of the vault to write to. Required only when multiple vaults are loaded.")
                        ])
                    ]),
                    "required": .array([.string("relative_path"), .string("content")])
                ]),
                annotations: writeAnnotations,
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "vault":         .object(["type": .string("string")]),
                        "relative_path": .object(["type": .string("string")]),
                        "content_hash":  .object(["type": .string("string")]),
                        "size_bytes":    .object(["type": .string("integer")]),
                        "created_at":    .object(["type": .string("string"), "format": .string("date-time")])
                    ]),
                    "required": .array([.string("vault"), .string("relative_path"), .string("content_hash"), .string("size_bytes"), .string("created_at")])
                ])
            ),
            Tool(
                name: "update_note",
                description: "Update an existing note. Mode 'replace' overwrites the entire file. Mode 'append' adds content to the end (with a leading newline if the file does not end in one). Mode 'prepend' inserts content after YAML frontmatter if present, or at the beginning of the file.",
                inputSchema: .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "relative_path": .object([
                            "type": .string("string"),
                            "description": .string("Vault-relative path of an existing note.")
                        ]),
                        "content": .object([
                            "type": .string("string"),
                            "description": .string("Markdown content to write.")
                        ]),
                        "mode": .object([
                            "type": .string("string"),
                            "enum": .array([.string("replace"), .string("append"), .string("prepend")]),
                            "description": .string("Write mode. 'replace' overwrites the full note. 'append' adds content to the end. 'prepend' adds content to the start (after any YAML frontmatter block, if present).")
                        ]),
                        "vault": .object([
                            "type": .string("string"),
                            "description": .string("Optional vault name; required only when 'relative_path' is ambiguous across multiple loaded vaults.")
                        ])
                    ]),
                    "required": .array([.string("relative_path"), .string("content"), .string("mode")])
                ]),
                annotations: writeAnnotations,
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "vault":         .object(["type": .string("string")]),
                        "relative_path": .object(["type": .string("string")]),
                        "mode":          .object(["type": .string("string")]),
                        "content_hash":  .object(["type": .string("string")]),
                        "size_bytes":    .object(["type": .string("integer")]),
                        "modified_at":   .object(["type": .string("string"), "format": .string("date-time")])
                    ]),
                    "required": .array([.string("vault"), .string("relative_path"), .string("mode"), .string("content_hash"), .string("size_bytes"), .string("modified_at")])
                ])
            )
        ]
    }
}
