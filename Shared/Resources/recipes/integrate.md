---
name: Integrate
description: Index and cross-reference notes the user dropped into the vault by hand.
kind: integrate
tool_allowlist:
  - Read
  - Grep
  - Glob
expected_output: wiki_operation
---

You are integrating user-dropped notes into a personal LLM wiki. The user wrote (or imported) these notes themselves — your job is to make them first-class wiki content alongside notes the agent created via Capture: indexed in `index.md`, cross-referenced from topically related pages, treated identically. **Do not move them, do not edit their bodies, do not add frontmatter.** Just index + cross-reference.

# Notes to integrate

{{input}}

# Vault snapshot

{{vault_state}}

# Your task

1. **Read `AGENTS.md`** — know this vault's `index.md` conventions before proposing changes.
2. **Read `index.md`** — you'll need its exact current contents byte-for-byte to propose a `modify`.
3. For each note path in the input list:
   - **Read the note.** Skim it just enough to know what it's about.
   - **Decide the right `index.md` section** — reuse existing sections wherever possible. Create a new section only if no existing one is even close. Match the formatting of existing entries.
   - **Add a `[[stem]]` entry** under that section in `index.md`. Use the note's filename without `.md` as the link text by default, or a friendlier display via `[[stem|Display Name]]` if the title in the file is meaningfully different.
   - **Cross-reference sparingly.** For each note, find at most **3 topically related existing pages** via `Grep`/`Glob`. Propose a small `modify` adding a `[[stem]]` link to each — only where the link is genuinely useful to a reader of that page. Skip if no obvious relation. Do not invent context, do not rewrite paragraphs, do not "improve" notes the user didn't ask you to touch. **No drive-by edits.**
4. Bundle every change into one `WikiOperation`. Keep `index.md` as a single `modify` with all additions accumulated, even when integrating many notes at once.

# Files you must NOT modify

- Anything under `raw/` — this folder is the user's immutable archive of source material. Don't pick `raw/` files as cross-reference targets, and never `modify` or `delete` a path beginning with `raw/`.
- Anything under `_audit/` — Review parks its artefacts there.
- The notes you're integrating themselves — only `index.md` and other already-curated wiki pages get touched. Do not add frontmatter, retitle, or alter the body of an integrated note.

# Modify preconditions

For every `{"type": "modify", ...}` change, you MUST have Read the target file in this session. The `before:` field must be the file's exact current contents — do not paraphrase or reconstruct from memory. If you didn't Read it, don't modify it.

# Output contract

When done, return ONLY a JSON object (no prose before or after):

```json
{
  "title": "integrate: <N notes>",
  "rationale": "one or two sentences summarising what got indexed and where",
  "changes": [
    {"type": "modify", "path": "index.md", "before": "...", "after": "..."},
    {"type": "modify", "path": "concepts/foo.md", "before": "...", "after": "..."}
  ]
}
```

An empty `changes` array means nothing needed integrating after all (rare — caller already filtered). Paths are vault-relative, forward slashes.
