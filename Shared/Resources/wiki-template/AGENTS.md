# AGENTS.md

This folder is a Clearly **LLM Wiki** — a personal knowledge base maintained
by an LLM on your behalf.

> **Humans read. The LLM writes.**
>
> You feed sources into `raw/`; the agent synthesizes them into wiki pages.
> Every change the agent wants to make surfaces as a diff you accept or
> reject. Nothing lands without your review.

## Layout

- `index.md` — content-oriented table of contents. Agent-maintained.
- `log.md` — chronological append-only record of every accepted operation.
  Each entry starts with `## [YYYY-MM-DD]` so `grep` queries work.
- `raw/` — immutable source material: articles, PDFs, clippings, transcripts.
  The agent reads from here but never edits it.
- `.clearly/recipes/` — editable prompt templates for Capture, Chat, and Review.

## Operations

Two manual actions are available from Clearly's **Wiki** menu. Review runs
quietly in the background when the vault opens.

- **Capture** (⌃⌘I). Paste a URL or text. The agent reads it, writes a
  summary page, updates `index.md`, cross-references related notes, and
  appends to `log.md`. Expect a single capture to touch 10–15 pages.

- **Chat** (⌃⌘A). Ask a question. The agent searches the wiki, reads relevant
  pages, and synthesizes an answer with inline citations. Good answers can
  be filed back as new pages so the wiki compounds.

- **Review**. The agent audits the wiki for contradictions, stale claims,
  orphan pages, missing cross-references, and concepts mentioned without their
  own page. Clearly runs this automatically about once a day; proposed changes
  appear as a "Review ready" badge.

## Conventions

- Use `[[wiki-links]]` for cross-references. Aliases (`[[Note|display text]]`)
  and section anchors (`[[Note#Section]]`) are supported.
- Use `#tags` sparingly. Tags supplement wiki-links; they don't replace them.
- YAML frontmatter is optional but encouraged for pages representing entities
  (people, concepts, projects) — it makes the agent's reasoning cleaner.
- File names are constants: **`AGENTS.md`**, **`index.md`**, **`log.md`**.
  Renaming any of the three removes this vault's wiki designation from
  Clearly's chrome.

## Capture checklist (what the agent should do)

1. Read the source end-to-end. Summarize to yourself.
2. Extract entities, concepts, and claims worth having their own pages.
3. Write the source summary page under a topic-relevant folder.
4. Add the source to `index.md` under the right category.
5. For each extracted entity/concept: either create its own page or update
   the existing one with the new information.
6. Cross-reference every related note via `[[wiki-links]]`.
7. Append one entry to `log.md` summarizing the operation.

## Review checklist (what the agent should do)

1. Orphan pages (zero inbound links) — suggest merges, redirects, or
   cross-references.
2. Stale claims — where a newer source contradicts or supersedes an older
   page, rewrite the page and add a "Last verified" note.
3. Missing entity pages — anywhere a name or concept is mentioned more than
   three times without its own page, create one.
4. Contradictions — where two pages disagree on a factual claim, surface
   both and the source of each.

Edit this file to tune the agent's behavior. Every Capture/Chat/Review run
reads this file as part of the context.
