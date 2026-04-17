# Live Editor QA Checklist

This is the runnable QA checklist for the experimental live preview editor.

Use it when validating the branch locally, preparing a draft PR, or re-checking behavior after bridge/editor changes.

## Preconditions

- Build and launch the app with:
  - `./script/build_and_run.sh`
- In `Settings > General`, set:
  - `Editor: Live Preview (Experimental)`
- Use disposable or version-controlled notes for destructive tests.
- Prefer testing with at least three note sizes:
  - small: 10-30 lines
  - medium: 150-400 lines
  - large: 1000+ lines with mixed markdown constructs

## Recommended Test Corpus

Prepare notes that cover:

- headings
- emphasis / strong / inline code
- markdown links
- wiki links
- tags
- lists / task lists
- blockquotes
- tables
- fenced code blocks
- math blocks
- mermaid fences
- local images

## Test Matrix

For each case, record `Pass`, `Fail`, or `Not Run` plus notes.

### 1. Document integrity

#### 1.1 Type, save, reopen

Steps:

1. Open an existing note.
2. Type normal markdown in multiple places.
3. Save.
4. Quit the app.
5. Reopen the same note.

Expected:

- content is preserved exactly
- no stale content reappears
- footer counts match the saved document

#### 1.2 Switch documents under edit pressure

Steps:

1. Open file A.
2. Type in file A.
3. Immediately switch to file B from the sidebar.
4. Switch back to file A.

Expected:

- file A retains the edit
- file B is not overwritten with file A content
- no blanking or flicker occurs

#### 1.3 Delete-all path

Steps:

1. Open a note with content.
2. Select all and delete everything.
3. Save.
4. Quit and reopen.

Expected:

- file remains empty
- previous content does not resurrect

#### 1.4 External file reload

Steps:

1. Open a note in Clearly.
2. Modify that file externally.
3. Return to Clearly.

Expected:

- updated content reloads
- old live-editor content does not overwrite the external change

### 2. Navigation and opening

#### 2.1 Sidebar open

Steps:

1. Open multiple notes in the sidebar tree.
2. Switch among them repeatedly.

Expected:

- each note opens correctly
- no note blanks on open

#### 2.2 Direct file open

Steps:

1. Open a markdown file directly with `Clearly Dev`.

Expected:

- the normal full workspace window appears
- the note content loads correctly

### 3. Input behavior

#### 3.1 Plain typing

Steps:

1. Type ordinary markdown across multiple lines.
2. Edit in the middle of existing text.
3. Backspace/delete rapidly.

Expected:

- typing is stable
- cursor does not jump unexpectedly
- characters are not dropped or duplicated

#### 3.2 Inline formatting

Steps:

1. Type markdown constructs such as `**bold**`, `*italic*`, links, tasks, and headings.
2. Move the caret across active and inactive lines.

Expected:

- inactive content renders live
- active editing stays stable
- formatting updates without requiring broken workarounds

#### 3.3 Paste behavior

Steps:

1. Paste plain markdown into the editor.
2. Paste while the find bar is focused.
3. Paste larger markdown blocks.

Expected:

- editor paste inserts content into the editor
- find-bar paste stays in the find field
- pasted markdown does not become a broken rich-text block

#### 3.4 Undo / redo

Steps:

1. Type and delete content.
2. Use `Cmd+Z` and `Shift+Cmd+Z`.

Expected:

- undo and redo operate on the live editor content correctly
- no stale state or blanking occurs

### 4. Search and commands

#### 4.1 Find

Steps:

1. Press `Cmd+F`.
2. Type a query.
3. Use next/previous navigation.
4. Paste into the field.

Expected:

- query stays in the field
- the field keeps focus while editing
- next/previous navigation works

#### 4.2 Menu formatting commands

Steps:

1. Select text in the live editor.
2. Run commands from `Format`.

Suggested commands:

- Bold
- Italic
- Link
- Bullet List
- Numbered List
- Todo List
- Quote
- Code Block

Expected:

- commands affect the live editor, not the classic editor path
- markdown source remains valid

#### 4.3 Outline navigation

Steps:

1. Open a note with multiple headings.
2. Use the outline to navigate between them.

Expected:

- the editor scrolls to the correct section
- no stale/incorrect offset jumps occur

### 5. Link routing

#### 5.1 Markdown links

Steps:

1. Interact with a normal markdown link in live mode.

Expected:

- the app performs the intended link action

#### 5.2 Wiki links and tags

Steps:

1. Interact with wiki links and tags in a note that contains them.

Expected:

- the correct routing callbacks fire
- no incorrect editor mutation occurs

### 6. Layout and responsiveness

#### 6.1 Resize narrow

Steps:

1. Gradually shrink the window width.

Expected:

- content reflows
- horizontal scrolling is not introduced prematurely
- wide tables remain horizontally scrollable only inside their wrapper

### 7. Performance

#### 7.1 Small note

Expected:

- no visible lag while typing

#### 7.2 Medium note

Expected:

- decorations stay responsive
- switching notes remains acceptable

#### 7.3 Large note

Expected:

- typing remains usable
- scrolling remains acceptable
- code fences / tables / math / Mermaid do not make the view unusable

#### 7.4 Large paste

Expected:

- the app remains responsive after paste

## Suggested Ownership Split

### Best done manually by a human

- plain typing feel
- undo / redo feel
- menu formatting commands
- markdown link / wiki link / tag routing
- outline navigation feel
- small / medium / large note performance
- resize behavior on a real window

### Good candidates for automation / code-driven validation

- build / bundle verification
- direct-open launch behavior
- sidebar open / switch stress
- external file mutation handling
- save / reopen corruption checks
- find field regression checks

## Result Template

Use this template for each run:

```text
Date:
Build:
Tester:

1.1 Type, save, reopen:
1.2 Switch documents under edit pressure:
1.3 Delete-all path:
1.4 External file reload:
2.1 Sidebar open:
2.2 Direct file open:
3.1 Plain typing:
3.2 Inline formatting:
3.3 Paste behavior:
3.4 Undo / redo:
4.1 Find:
4.2 Menu formatting commands:
4.3 Outline navigation:
5.1 Markdown links:
5.2 Wiki links and tags:
6.1 Resize narrow:
7.1 Small note:
7.2 Medium note:
7.3 Large note:
7.4 Large paste:

Notes:
```
