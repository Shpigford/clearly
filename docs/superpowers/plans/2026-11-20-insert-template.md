# Insert Template Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepend a vault `Templates/*.md` file into an existing Mac note, with `{{date}}` / `{{time}}` / `{{title}}` substitution and Dataview/JS stripped.

**Architecture:** Pure engine in ClearlyCore (`NoteTemplateEngine`) lists templates, strips query fences, expands placeholders, and joins prefix + existing text. `WorkspaceManager.insertTemplate` applies that string to an open buffer or to disk. The Mac sidebar and an AppKit-injected Edit menu call that method.

**Tech Stack:** Swift 5 / ClearlyCore, Swift Testing, SwiftUI sidebar menus, AppKit menu injection.

**Spec:** `docs/superpowers/specs/2026-11-20-insert-template-design.md`

## Global Constraints

- Mac-only UI; engine must be `public` in ClearlyCore.
- Templates folder name is exactly `Templates` at the vault root.
- Placeholders: `{{date}}` → `yyyy-MM-dd`, `{{time}}` → `HH:mm`, `{{title}}` → filename without `.md`. DateFormatter locale `en_US_POSIX`, current timezone.
- Do not execute JavaScript or Dataview.
- Hotkey is `⌥⌘I`, injected via AppKit. Do not bind `⌥⌘T` (Hide Toolbar). Do not use SwiftUI `.keyboardShortcut` with `[.command, .option]`.
- Commit scopes: `[shared]` for ClearlyCore, `[mac]` for app UI.
- After adding ClearlyCore sources, run `xcodegen generate`.
- Vault file IO goes through `CoordinatedFileIO`.

## Review Focus

- Active document in **preview / WYSIWYG**: EditorView may be unmounted, so the prepend notification must not be the only write path — `WorkspaceManager` still assigns `openDocuments[i].text` / `currentFileText` and bumps `documentEpoch`.
- Closed file that later gets a FileWatcher event: disk prepend must look like any other external write; the open-file path must not also write disk (that would race autosave).
- Right-click a **background tab's** file: insert into that tab's buffer, not the active document, and do not call `insertText` on the active editor.
- Inserting a template into a note that already starts with the same template: still prepend (no dedup). Engine test `renderPrependsEvenWhenExistingStartsWithTemplate`.
- Hide Toolbar `⌥⌘T` still toggles after the new Edit-menu item exists (manual verify in Task 2).

---

## File map

- Create: `Packages/ClearlyCore/Sources/ClearlyCore/Vault/NoteTemplate.swift` — `NoteTemplate` + `NoteTemplateEngine`
- Create: `Packages/ClearlyCore/Tests/ClearlyCoreTests/NoteTemplateTests.swift`
- Modify: `Clearly/WorkspaceManager.swift` — `templates(forFile:)` + `insertTemplate(_:into:)`
- Modify: `Clearly/Native/MacFolderSidebar.swift` — `fileContextMenu` submenu
- Modify: `Clearly/Native/NativeShellSupport.swift` — `Notification.Name.prependTemplate`
- Modify: `Clearly/EditorView.swift` — prepend observer using `insertText` at location 0
- Modify: `Clearly/ClearlyApp.swift` — inject Edit → Insert Template + `⌥⌘I`

---

### Task 1: NoteTemplateEngine

**Files:**
- Create: `Packages/ClearlyCore/Sources/ClearlyCore/Vault/NoteTemplate.swift`
- Create: `Packages/ClearlyCore/Tests/ClearlyCoreTests/NoteTemplateTests.swift`

**Interfaces:**
- Consumes: Foundation `FileManager`, `DateFormatter`
- Produces:

```swift
public struct NoteTemplate: Equatable, Identifiable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String // filename without `.md`
}

public struct NoteTemplateRender: Equatable, Sendable {
    public let prefix: String    // expanded template, already joined for prepend
    public let combined: String  // prefix + existing
}

public enum NoteTemplateEngine {
    public static let folderName = "Templates"

    public static func list(in vaultRoot: URL, fileManager: FileManager = .default) -> [NoteTemplate]

    public static func render(
        template: String,
        title: String,
        now: Date,
        existingText: String
    ) -> NoteTemplateRender
}
```

`list`: non-recursive `Templates/*.md`, skip names with prefix `.`, skip non-files, sort by `name.localizedStandardCompare`. Missing folder → `[]`.

`render`: (1) strip fenced blocks whose info string is `dataview` or `dataviewjs` (case-insensitive), including lines prefixed with `>` / `> `; (2) drop leftover `> [!…]` callout blocks whose body is only blank `>` lines; (3) collapse 3+ consecutive newlines to `\n\n`; (4) replace `{{date}}`, `{{time}}`, `{{title}}`; (5) if `existingText` is empty, `prefix = expanded`, `combined = expanded`; else `prefix = expanded.trimmingCharacters(in: .newlines) + "\n\n"`, `combined = prefix + existingText`.

- [ ] **Step 1: Write the failing tests** in `NoteTemplateTests.swift` using Swift Testing.

Pin these cases (fixed `now = Date(timeIntervalSince1970: 1_766_044_800)` → date `2025-12-18` in local tz is **wrong** — do not use a unix timestamp; construct `DateComponents(calendar: .init(identifier: .gregorian), timeZone: .current, year: 2026, month: 11, day: 20, hour: 15, minute: 4)` and format with the same rules as production):

```swift
@Test func listMissingFolderReturnsEmpty()
@Test func listReadsTopLevelMarkdownSortedByName()
@Test func listSkipsHiddenAndNestedFiles()
@Test func renderSubstitutesDateTimeTitle()
@Test func renderStripsDataviewJSFence()
@Test func renderStripsQuotedDataviewCallouts()
@Test func renderJoinsWithBlankLineWhenExistingNonEmpty()
@Test func renderKeepsTemplateOnlyWhenExistingEmpty()
@Test func renderPrependsEvenWhenExistingStartsWithTemplate()
```

Assertions to pin:

- `list` of a temp vault with `Templates/Project.md`, `Templates/abstract.md`, `Templates/.hidden.md`, `Templates/nested/x.md` → names `["abstract", "Project"]` (localizedStandardCompare order).
- Template `"# {{title}}\n{{date}} {{time}}\n"` + title `"Hash Map"` + the fixed date → combined contains `"# Hash Map"`, `"2026-11-20"`, `"15:04"`.
- Daily-style input with a ` ```dataviewjs ` fence between `# задачи из now` and `### to-do list` → output has those two headings and **no** `dataviewjs` / `dv.` / `dv.table`.
- Project-style input with two `> [!todo]` callouts each wrapping `> ```dataview` fences → output has `# Todo List` and does **not** contain `[!todo]`, `dataview`, or `where !completed`.
- Existing `"body"` + template `"# T\n"` → combined `"# T\n\nbody"`.
- Existing `""` → combined equals expanded template (no extra `\n\n` invented beyond what the template already has).
- Existing already starting with `"# T\n\n"` still prepends another `"# T\n\n"`.

- [ ] **Step 2: Run tests, expect FAIL** (type not found)

```
swift test --package-path Packages/ClearlyCore --filter NoteTemplateTests
```

- [ ] **Step 3: Implement `NoteTemplate` + `NoteTemplateEngine` in `Packages/ClearlyCore/Sources/ClearlyCore/Vault/NoteTemplate.swift`**

DateFormatter: `en_US_POSIX`, `yyyy-MM-dd` and `HH:mm`, `timeZone = .current`. Fence stripper is a small scanner/regex over the raw template **before** placeholder expansion so query bodies cannot inject `{{title}}`.

- [ ] **Step 4: Run tests, expect PASS**

```
swift test --package-path Packages/ClearlyCore --filter NoteTemplateTests
```

- [ ] **Step 5: `xcodegen generate`** so the new ClearlyCore file is in the Xcode project.

- [ ] **Step 6: Commit**

```
git add Packages/ClearlyCore/Sources/ClearlyCore/Vault/NoteTemplate.swift \
        Packages/ClearlyCore/Tests/ClearlyCoreTests/NoteTemplateTests.swift \
        Clearly.xcodeproj
git commit -m "[shared] Add NoteTemplate engine for vault Templates folder"
```

---

### Task 2: Mac insert path (sidebar, editor, ⌥⌘I)

**Files:**
- Modify: `Clearly/WorkspaceManager.swift`
- Modify: `Clearly/Native/MacFolderSidebar.swift` (`fileContextMenu` around line 507)
- Modify: `Clearly/Native/NativeShellSupport.swift`
- Modify: `Clearly/EditorView.swift`
- Modify: `Clearly/ClearlyApp.swift` (`applicationWillUpdate` + new inject)

**Interfaces:**
- Consumes: `NoteTemplateEngine.list`, `NoteTemplateEngine.render`
- Produces:

```swift
// WorkspaceManager
func templates(forFile url: URL) -> [NoteTemplate]
@discardableResult
func insertTemplate(_ template: NoteTemplate, into fileURL: URL) -> Bool

// Notification.Name.prependTemplate
// userInfo: ["text": String]  // render.prefix only
```

`templates(forFile:)`: `containingVaultRoot(for: url).map { NoteTemplateEngine.list(in: $0) } ?? []`.

`insertTemplate`:
1. Read template with `CoordinatedFileIO.read`; on failure log and return `false`.
2. `title = fileURL.deletingPathExtension().lastPathComponent`.
3. Resolve existing text: matching `openDocuments` entry's `.text` if open, else `String(data: CoordinatedFileIO.read(at: fileURL), encoding: .utf8)`.
4. `let render = NoteTemplateEngine.render(template:title:now:existingText:)`.
5. If `fileURL` is in `openDocuments`:
   - Assign `openDocuments[i].text = render.combined` (do **not** change `lastSavedText`).
   - If that document is **active**:
     - If `currentViewMode == .edit`, post `.prependTemplate` with `render.prefix` and do **not** assign `currentFileText` (the editor binding will).
     - Else assign `currentFileText = render.combined`, bump `documentEpoch`, `WYSIWYGSession.update(documentID:epoch:)`.
   - If that document is **not** active: do not post the notification and do not touch `currentFileText`.
6. If not open: `CoordinatedFileIO.write(Data(render.combined.utf8), to: fileURL)`.
7. Return `true` on success.

EditorView: observe `.prependTemplate`; `textView.insertText(prefix, replacementRange: NSRange(location: 0, length: 0))`. Guard that this text view is first responder / in a window so a leftover observer from a dismantled view cannot insert. `dismantleNSView` already `removeObserver`s the coordinator.

Sidebar: in `fileContextMenu`, after Pin / Open in New Tab:

```swift
let templates = workspace.templates(forFile: url)
Menu("Insert Template") {
    ForEach(templates) { template in
        Button(template.name) {
            workspace.insertTemplate(template, into: url)
        }
    }
}
.disabled(templates.isEmpty)
```

AppDelegate `injectInsertTemplateIfNeeded()` from `applicationWillUpdate`:
- Target the **Edit** menu.
- Item title `Insert Template`, tag a dedicated `insertTemplateMenuItemTag`, submenu rebuilt from `WorkspaceManager.shared.templates(forFile:)` using `currentFileURL`.
- `keyEquivalent = "i"`, `keyEquivalentModifierMask = [.command, .option]`.
- Disabled when `currentFileURL == nil` or templates empty.
- Action on each submenu item calls `insertTemplate` into `currentFileURL`.
- Guard like other injectors so SwiftUI's Edit-menu rebuild does not duplicate the item.

Do **not** add a SwiftUI `.keyboardShortcut("i", modifiers: [.command, .option])`.

- [ ] **Step 1: Implement `templates(forFile:)` and `insertTemplate(_:into:)` on `WorkspaceManager`** with the control flow above.

- [ ] **Step 2: Add `.prependTemplate` and the EditorView observer** that inserts `userInfo["text"]` at location 0.

- [ ] **Step 3: Add the sidebar `Menu("Insert Template")`** in `fileContextMenu` only (not folder / vault header menus).

- [ ] **Step 4: Inject Edit → Insert Template + `⌥⌘I`** in `ClearlyAppDelegate.applicationWillUpdate`.

- [ ] **Step 5: `xcodegen generate` if `project.yml` / file list changed, then build**

```
xcodegen generate
xcodebuild -scheme Clearly -configuration Debug build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Manual verify** (no UI unit tests)

  - Open a vault that has `Templates/` like the four Obsidian files.
  - Right-click a note → Insert Template → abstract: frontmatter + `# <filename>` at the top, `дата создания` is today, no dataview.
  - Insert Project into a non-empty note: `#project` / Todo List headings appear **above** existing text; no `[!todo]` / `dataview`.
  - `⌘Z` after inserting into the active editor undoes the prepend.
  - Right-click a file that is not the active tab: that file's buffer/disk changes, the visible editor does not.
  - `⌥⌘I` inserts via the Edit submenu for the active file.
  - `⌥⌘T` still toggles Hide Toolbar.
  - Vault with no `Templates/` folder: menu disabled.

- [ ] **Step 7: Commit**

```
git add Clearly/WorkspaceManager.swift \
        Clearly/Native/MacFolderSidebar.swift \
        Clearly/Native/NativeShellSupport.swift \
        Clearly/EditorView.swift \
        Clearly/ClearlyApp.swift
git commit -m "[mac] Insert Template from sidebar and Edit menu"
```
