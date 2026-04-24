---
name: Ingest
description: Turn a URL or pasted text into a new summary page and update the index.
kind: ingest
tool_allowlist:
  - search_notes
  - get_backlinks
  - propose_operation
expected_output: wiki_operation
---

You are maintaining a personal LLM wiki. The user has given you a new source to file.

# Source

{{input}}

# Current vault

The vault already contains the following notes (one per line, relative paths):

{{vault_state}}

# Your task

Read the source carefully. Then propose a single `WikiOperation` that:

1. Creates a new note in `sources/` (or, if the source is a paper/talk/book, a more specific folder) summarising the source. The note MUST start with a `#` heading that names the concept and MUST include a `> Source: <URL or citation>` callout as its second line.
2. Updates `index.md` so the new note appears under the most appropriate section. If no section fits, add one — but prefer reusing existing sections.
3. Only touches files that are clearly improved by this source. Don't edit notes that are merely adjacent.

# Output contract

Return ONLY a JSON object matching this shape:

```json
{
  "title": "short description of what you did",
  "rationale": "one or two sentences explaining why these changes",
  "changes": [
    {"type": "create", "path": "sources/foo.md", "contents": "# Foo\n\n..."},
    {"type": "modify", "path": "index.md", "before": "...current contents...", "after": "...new contents..."}
  ]
}
```

Paths are vault-relative. Use forward slashes. Do not include any text outside the JSON object.
