---
title: Clearly — A Native Markdown Editor for macOS
author: Josh Pigford
date: 2026-04-11
tags: markdown, macos, swiftui, demo
---

# Clearly

A **native macOS markdown editor** built with SwiftUI — fast, focused, and beautifully rendered. This document shows off everything Clearly can do.

> "The best tool is the one that gets out of your way." — *somebody, probably*

---

## Headings

# H1 — The biggest statement
## H2 — Section header
### H3 — Subsection
#### H4 — Smaller grouping
##### H5 — Smaller still
###### H6 — The smallest

---

## Text Formatting

You can write in **bold**, *italic*, ***bold italic***, or ~~strikethrough~~. Combine them inline: this sentence has **bold with *nested italic* inside** for emphasis.

Use `inline code` for short snippets, variable names like `NSTextStorage`, or file paths like `~/Desktop/demo.md`.

Links look like this: [Clearly on GitHub](https://github.com/joshpigford/clearly), and autolinked URLs work too: https://apple.com.

---

## Lists

### Unordered

- First item
- Second item
  - Nested item
  - Another nested item
    - Even deeper
- Third item

### Ordered

1. Draft the idea
2. Write it down
3. Ship it
   1. Build
   2. Test
   3. Release

### Task List

- [x] Open a markdown file
- [x] See beautiful syntax highlighting
- [x] Render a live preview
- [ ] Tell all your friends
- [ ] World domination

---

## Blockquotes

> Simplicity is the ultimate sophistication.
>
> > Nested blockquotes work too — useful for threaded replies or layered citations.
>
> — Leonardo da Vinci

---

## Code

Inline: use `cmd + 1` for editor mode and `cmd + 2` for preview mode.

Fenced code block with a language hint:

```swift
import SwiftUI

@main
struct ClearlyApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
```

```python
def fibonacci(n: int) -> list[int]:
    seq = [0, 1]
    for _ in range(n - 2):
        seq.append(seq[-1] + seq[-2])
    return seq

print(fibonacci(10))
```

```bash
# Build Clearly from the command line
xcodegen generate
xcodebuild -scheme Clearly -configuration Debug build
```

---

## Tables

### Feature Matrix (centered alignment)

| Feature              | Editor | Preview | QuickLook |
| :------------------- | :----: | :-----: | :-------: |
| Syntax highlighting  |   ✓    |    —    |     —     |
| Live GFM rendering   |   —    |    ✓    |     ✓     |
| Tables               |   ✓    |    ✓    |     ✓     |
| Math (KaTeX)         |   ✓    |    ✓    |     ✓     |
| Mermaid diagrams     |   ✓    |    ✓    |     ✓     |
| Task lists           |   ✓    |    ✓    |     ✓     |

### Right-aligned numbers

Numbers align cleanly in right-aligned columns — try clicking column headers to sort.

| Item       | Qty | Price   |
| ---------- | --: | ------: |
| Coffee     |   2 |  $8.50  |
| Croissant  |   1 |  $4.25  |
| Donut      |   3 |  $9.00  |
| Juice      |   1 |  $5.50  |
| **Total**  |   7 | **$27.25** |

### Table Captions

A paragraph starting with "Table:" immediately before a table becomes a caption.

Table: Quarterly revenue by region (in thousands)

| Region        | Q1    | Q2    | Q3    | Q4    |
| ------------- | ----: | ----: | ----: | ----: |
| North America | $142  | $158  | $171  | $195  |
| Europe        | $98   | $105  | $112  | $128  |
| Asia Pacific  | $67   | $82   | $91   | $103  |

### Wide Table (horizontal scroll)

Tables wider than the viewport scroll horizontally inside their container.

| Metric | January | February | March | April | May | June | July | August | September | October | November | December |
| ------ | ------: | -------: | ----: | ----: | --: | ---: | ---: | -----: | --------: | ------: | -------: | -------: |
| Users  | 1,200   | 1,450    | 1,800 | 2,100 | 2,400 | 2,750 | 3,100 | 3,500 | 3,900 | 4,200 | 4,600 | 5,100 |
| Revenue | $12k   | $14.5k   | $18k  | $21k  | $24k | $27.5k | $31k | $35k  | $39k  | $42k  | $46k  | $51k  |

---

## Math (KaTeX)

Inline math flows with your prose: the quadratic formula is $x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}$, and Euler's identity $e^{i\pi} + 1 = 0$ still feels like magic.

Display math sits on its own line:

$$
\int_{-\infty}^{\infty} e^{-x^2} \, dx = \sqrt{\pi}
$$

---

## Mermaid Diagrams

```mermaid
flowchart LR
    A[Write Markdown] --> B{Mode?}
    B -->|⌘1| C[Editor]
    B -->|⌘2| D[Preview]
    C --> E[Syntax Highlighting]
    D --> F[Live HTML]
    E --> G[Save .md]
    F --> G
```

```mermaid
sequenceDiagram
    participant U as User
    participant E as Editor
    participant R as Renderer
    U->>E: Types markdown
    E->>E: Highlight syntax
    U->>R: ⌘2 (Preview)
    R->>R: cmark-gfm → HTML
    R-->>U: Rendered preview
```

---

## Horizontal Rules

Three dashes, asterisks, or underscores all work:

---

***

___

---

## Images

![Clearly Screenshot](https://raw.githubusercontent.com/Shpigford/clearly/main/website/screenshot.jpg)

---

## Footnotes

Clearly renders GitHub-style footnotes[^1], including multiple references[^note] in the same paragraph[^1].

[^1]: This is the first footnote. It can contain **formatting** and `code`.
[^note]: Named footnotes work too — use any label you like.

---

## Escapes & Edge Cases

Use backslashes to escape markdown: \*not italic\*, \`not code\`, \# not a heading.

HTML passes through for when you need it:

<kbd>⌘</kbd> + <kbd>S</kbd> to save, <kbd>⌘</kbd> + <kbd>F</kbd> to find.

---

## The End

That's Clearly — **every markdown feature you actually use**, rendered beautifully, highlighted live, and ready to ship. 🚀
