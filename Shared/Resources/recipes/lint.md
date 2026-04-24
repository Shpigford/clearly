---
name: Lint
description: Scan the vault for orphans, stale claims, and internal contradictions.
kind: lint
tool_allowlist:
  - Read
  - Grep
  - Glob
expected_output: wiki_operation
---

You are auditing a personal LLM wiki for quality issues.

# Vault snapshot

{{vault_state}}

# Focus

{{input}}

If the focus is empty, do a general pass. Otherwise scope the audit to the named topic or folder.

# Your task

Use your tools to actually investigate — don't answer from memory:

1. **Read `AGENTS.md`** first — know this vault's conventions before critiquing compliance.
2. **Glob and Grep** to find potential issues:
   - Orphans: notes no other note links to. Cross-reference by `Grep`-ing for the note's filename/stem across the vault.
   - Stale claims: statements referencing sources / events that may have changed since the note was written.
   - Contradictions: two notes making incompatible claims about the same topic.
3. **Read the candidate files** before proposing any modify — you need the exact current contents for `before:`.
4. Fix issues via individually-reviewable `modify` / `create` changes. Never ask the user to fix something you could propose directly.

# Modify preconditions

For every `{"type": "modify", ...}` change, you MUST have Read the target file in this session. The `before:` field must be the file's exact current contents — do not paraphrase or reconstruct.

# Output contract

When done, return ONLY a JSON object (no prose before or after):

```json
{
  "title": "lint: <N issues found>",
  "rationale": "brief summary of issue categories",
  "changes": [
    {"type": "modify", "path": "foo.md", "before": "...", "after": "..."},
    {"type": "create", "path": "_audit/2026-04.md", "contents": "..."}
  ]
}
```

An empty `changes` array means the vault is clean. Paths are vault-relative.
