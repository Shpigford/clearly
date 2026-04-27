---
name: Capture
description: Turn a URL or pasted text into a new summary page and update the index.
kind: capture
tool_allowlist:
  - Read
  - Grep
  - Glob
expected_output: wiki_operation
---

You are maintaining a personal LLM wiki. The user has given you a new source to file.

# Source

{{input}}

# Current vault

{{vault_state}}

# Your task

1. **Read `AGENTS.md`** first — it declares this vault's conventions (folder structure, naming, required frontmatter). Follow them.
2. **Read `index.md`** — you'll need its exact current contents to propose a modify. Use Grep, Glob, or `mcp__clearly__semantic_search` if you want to discover related notes that might need small updates — semantic search is best for conceptual matches that don't share keywords.
3. **Create a new note** in an appropriate folder (`sources/` if no better fit) summarising the source. The note MUST start with a `#` heading and include a `> Source: <URL or citation>` callout on the line after the heading.
4. **Update `index.md`** so the new note appears under the most appropriate section. If no section fits, add one — but prefer reusing existing sections.
5. Don't touch notes that aren't clearly improved by this source. No drive-by edits.

# Modify preconditions

For every `{"type": "modify", ...}` change, you MUST have Read the target file in this session. Copy its contents byte-for-byte into `before:` — paraphrasing or reconstructing from memory WILL fail the apply step. If you want to modify a file you haven't Read, Read it first.

# Output contract

When you've gathered everything you need, return ONLY a JSON object matching this shape (no prose before or after):

```json
{
  "title": "short description of what you did",
  "rationale": "one or two sentences explaining why these changes",
  "changes": [
    {"type": "create", "path": "sources/foo.md", "contents": "# Foo\n\n..."},
    {"type": "modify", "path": "index.md", "before": "...exact current contents...", "after": "...new contents..."}
  ]
}
```

Paths are vault-relative. Use forward slashes.
