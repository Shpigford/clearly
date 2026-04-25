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

## How it works

- Every change is reviewed in a diff sheet. Nothing lands without your approval.
- Once a day Clearly quietly reviews the wiki for orphans and inconsistencies.
  When it finds something, the sidebar gets a small badge — click to review.
- Your wiki is plain markdown on disk. Edit anything by hand whenever you want.

Delete this note when you don't need it anymore.
