# Welcome to your wiki

This is an **LLM wiki** — a personal knowledge base you grow by reading.
The idea is borrowed from [Andrej Karpathy's gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f):
when you come across something worth keeping (an article, a conversation,
an idea), you hand it to the agent. The agent reads it, extracts what
matters, writes notes, links related ones, and keeps `index.md` tidy.
You review every change. Over time the wiki compounds into something
genuinely useful and personal — yours.

You stay in charge. The agent proposes; you accept or reject. Notes link
to each other with `[[wiki-links]]` — click one to jump.

## Three commands

- ⌃⌘I — **Capture**: paste a URL or any text. The agent reads it, writes
  a note, and updates `index.md`. You review the diff before anything lands.
- ⌃⌘A — **Chat**: ask questions. The agent reads the relevant notes and
  cites them with `[[wiki-links]]`.
- ⌃⌘T — **Toggle Log Sidebar**: scrubbable timeline of what changed and when.

## Drop in your own notes

Capture is for when you want the agent to synthesize a note from a
source. If you already know what you want to write, just drop a `.md`
file into this folder — drag from Finder, drop onto a folder in the
sidebar, or press ⌘N and save here. Wherever you put it is where it
stays — Clearly never moves your notes around.

Shortly after you drop a note, an Integrate pass runs in the background:
it adds the note to `index.md` under the right section and proposes
`[[wiki-link]]` cross-references in topically related pages. You review
the diff before anything lands. Hand-dropped notes are treated
identically to agent-created ones.

For raw source material (articles, PDFs, transcripts) you want the agent
to read later, drop the file into `raw/`. The agent reads from there but
never edits it.

## How it works

- Every change is reviewed in a diff sheet. Nothing lands without your approval.
- Once a day Clearly quietly reviews the wiki for orphans and inconsistencies.
  When it finds something, the sidebar gets a small badge — click to review.
- Your wiki is plain markdown on disk. Edit anything by hand whenever you want.

Delete this note when you don't need it anymore.
