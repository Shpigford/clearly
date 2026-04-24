---
name: Lint
description: Scan the vault for orphans, stale claims, and internal contradictions.
kind: lint
tool_allowlist:
  - search_notes
  - get_backlinks
  - get_tags
  - list_orphans
  - list_stale
  - propose_operation
expected_output: wiki_operation
---

You are auditing a personal LLM wiki for quality issues.

# Vault snapshot

{{vault_state}}

# Focus

{{input}}

If the focus is empty, do a general pass. Otherwise scope the audit to the named topic or folder.

# Your task

Look for:

1. **Orphans** — notes nobody links to. Either cross-link them from a relevant existing note, or flag them for deletion.
2. **Stale claims** — statements that reference a source or event that has since changed.
3. **Contradictions** — two notes making incompatible claims about the same topic.

Do NOT fix issues silently. Every fix you propose must be reviewable as an individual file change.

# Output contract

Return ONLY a JSON object:

```json
{
  "title": "lint: <N issues found>",
  "rationale": "brief summary of issue categories",
  "changes": [
    {"type": "modify", "path": "foo.md", "before": "...", "after": "..."},
    {"type": "create", "path": "index.md", "contents": "..."}
  ]
}
```

An empty `changes` array means the vault is clean. Paths are vault-relative. No text outside the JSON.
