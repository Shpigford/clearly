# Wiki feature progress

## Status: Phases 1, 2, 3, 4 — Completed; Phase 5 — Code complete, awaiting manual verification

## Quick Reference
- Research: `docs/wiki/RESEARCH.md`
- Implementation: `docs/wiki/IMPLEMENTATION.md`
- Source plan: `~/.claude/plans/melodic-questing-blossom.md`
- Branch: `llm-wiki-exploration`

---

## Phase Progress

### Phase 1: Drop the Anthropic API-key path
**Status:** Completed
**Commit scope:** `[mac]`

#### Tasks
- [x] Delete `Packages/ClearlyCore/Sources/ClearlyCore/Wiki/AnthropicAPIAgentRunner.swift`
- [x] Delete `Packages/ClearlyCore/Sources/ClearlyCore/Wiki/KeychainStore.swift`
- [x] Delete `Packages/ClearlyCore/Tests/ClearlyCoreTests/KeychainStoreTests.swift`
- [x] Strip the two `AnthropicAPIAgentRunner.decode` test methods from `Packages/ClearlyCore/Tests/ClearlyCoreTests/AgentRunnerTests.swift`
- [x] `WikiAgentCoordinator.swift`: remove `promptForAPIKey()` and `promptSecret(...)`
- [x] `WikiAgentCoordinator.swift`: rewrite `resolveToolEnabledRunner(vaultURL:)` to CLI-only
- [x] `WikiAgentCoordinator.swift`: drop BYOK fallback paragraphs from error strings in `sendChatMessage` and `beginSession`
- [x] `WikiAgentCoordinator.swift`: drop the `AgentError.missingAPIKey` arm of `describe(_:)`
- [x] `AgentRunner.swift`: remove `case missingAPIKey` from `AgentError`
- [x] `ClearlyApp.swift`: delete the `Divider()` + `Set Anthropic API Key…` button
- [x] Run `xcodegen generate`
- [x] Verify: `xcodebuild Debug build` clean
- [x] Verify: `swift test` clean (88 tests, was 95 — minus 7 KeychainStoreTests + 2 Anthropic decode tests)
- [x] Verify: grep returns no hits for `anthropicAPIKey|AnthropicAPIAgentRunner|KeychainStore|WikiKeychainAccount|promptForAPIKey|promptSecret|missingAPIKey|"Set Anthropic API Key"`
- [x] Manual: with `claude` installed → Chat works. Without → install message, no key prompt.

#### Decisions Made
- Bundled `Packages/ClearlyCore/Package.resolved` cleanup into the `[mac]` commit. The `eventsource` pin removal is directly caused by deleting `AnthropicAPIAgentRunner` (its SSE transitive dep). Other pin removals (sparkle, keyboardshortcuts, swift-sdk, etc.) were stale entries that don't belong in the `ClearlyCore` package's resolve file — `swift test` rewrote the file to match the package's actual deps (`cmark-gfm`, `grdb.swift`).
- Per CLAUDE.md scope rule "pick the most-specific user-visible scope": even though deletions hit `Packages/ClearlyCore/`, the user-visible result (no more BYOK key UI) is Mac-only — iOS never exposed it. `[mac]` is correct.

#### Blockers
- (none)

---

### Phase 2: Seed `getting-started.md` on wiki creation
**Status:** Completed
**Commit scope:** `[mac]`

#### Tasks
- [x] Create `Shared/Resources/wiki-template/getting-started.md` with welcome content (sparse, three-command focused)
- [x] `WikiSeeding.swift` lines 27–36: add fifth `(src, dst)` entry for `getting-started.md`
- [x] Rebind Wiki → Chat shortcut from ⌃⌘Q (macOS lock-screen) to ⌃⌘A in `ClearlyApp.swift:1054`
- [x] After File → New LLM Wiki seeds the vault, auto-open `getting-started.md` so the welcome doc is the active document (`WikiSeeder.createNewWiki`, new-location branch only)
- [x] Expand welcome content: framing paragraph linking Karpathy's gist + "you stay in charge" stance, before the three-command list
- [x] Add "Drop in your own notes" section to welcome doc explaining the manual-drop / `raw/` workflow alongside Capture
- [x] Catch stale ⌃⌘Q references in `Shared/Resources/wiki-template/AGENTS.md` and the `WikiAgentCoordinator.startChat` doc-comment
- [x] Run `xcodegen generate`
- [x] Verify: `xcodebuild Debug build` clean
- [x] Verify: `swift test` clean (90/90 — was 88; 2 new tests in unrelated working-tree work)
- [x] Verify: bundled `Clearly Dev.app/Contents/Resources/wiki-template/` contains all 5 files
- [x] Manual: File → New LLM Wiki → folder gets 5 top-level files including `getting-started.md`, and `getting-started.md` is the active document with sidebar selection on it
- [x] Manual: Convert-to-LLM-Wiki on existing folder with a hand-written `getting-started.md` doesn't overwrite it; user's current document is NOT yanked away
- [x] Manual: Wiki → Chat fires on ⌃⌘A; ⌃⌘Q now hits the OS lock-screen prompt instead

#### Decisions Made
- Path correction: source plan and IMPLEMENTATION.md said `Clearly/Resources/wiki-template/` — actual directory is `Shared/Resources/wiki-template/` (per `project.yml:60` and `WikiSeeding.swift:22`). Used the real path.
- Bundled the Chat shortcut rebind (⌃⌘Q → ⌃⌘A) into Phase 2 because the welcome content documents the shortcut. Shipping `getting-started.md` with `⌃⌘Q` would have taught users a binding that locks the screen on macOS Ventura+. ⌃⌘A is the 'A for Ask' mnemonic, free both system-wide and in Clearly (verified via `grep keyboardShortcut Clearly/`).

#### Blockers
- (none)

---

### Phase 3: Auto-Review on vault open with sidebar badge
**Status:** Completed (awaiting manual verification)
**Commit scope:** `[mac]`

#### Tasks
**A. Per-vault state**
- [x] Create `Clearly/Wiki/WikiVaultState.swift` (`Codable` struct + `read(at:)` and `recordReviewRun(at:)` helpers)
- [x] State file location: `<vault>/.clearly/state.json`; read fails closed → returns `nil` → treated as stale

**B. Controller `holdForReview`**
- [x] `WikiOperationController.swift`: add `pendingOperation`, `pendingVaultRoot`, `hasPendingReview`, `holdForReview(_:vaultRoot:)`, `presentPending()`
- [x] Keep pending state independent from staged state; `dismiss()` records handled Review cooldown only after the user opens and dismisses/accepts the staged Review

**C. Trigger + integration**
- [x] `WikiAgentCoordinator.swift`: replace `startReview(workspace:controller:)` with `runReviewIfStale(workspace:controller:)` — drops focus prompt, gates on 24h cooldown, silent on missing `claude` CLI / agent failure
- [x] `WikiAgentCoordinator.runRecipe`: add `stageMode: StageMode` param (`.immediate | .holdForReview`) — auto-Review parks results on `pendingOperation` instead of staging
- [x] `WikiAgentCoordinator.runRecipe`: record `WikiVaultState.recordReviewRun` immediately only for empty Review results; non-empty held Reviews record when the staged Review is handled
- [x] `MacDetailColumn.swift`: extend `.onAppear`, `onChange(of: activeLocation?.id)`, and `onChange(of: treeRevision)` to call `runReviewIfStale`
- [x] Delete stale `.wikiReview` notification observer so no callers reference deleted `startReview`

**D. Badge UI**
- [x] `WikiLogSidebar.swift`: accepts `controller: WikiOperationController`; renders pending badge above the existing header row (tinted dot · "Review ready · N changes" · chevron) when `hasPendingReview`. Click → `presentPending()`
- [x] Skipped: optional dot on Wiki menu's "Toggle Log Sidebar" item — sidebar badge is sufficient

**E. Remove Review menu item**
- [x] `ClearlyApp.swift`: deleted `Review` button + ⌃⌘L shortcut. Kept `OperationKind.review` enum case (still used by auto-Review path and log entries)

**Verify**
- [x] `xcodegen generate` clean
- [x] `xcodebuild Debug build` clean
- [x] `swift test` clean (93/93)
- [ ] Manual A: force `lastReviewAt` 25h ago → Review fires silently, badge appears, click → diff sheet opens
- [ ] Manual B: reopen within 24h → no fire (DiagnosticLog confirms skip)
- [ ] Manual C: empty Review result still records timestamp (won't re-fire next launch)
- [ ] Manual D: Wiki menu has no Review item; ⌃⌘T still works
- [ ] Manual E: with `claude` not installed → silent no-op, no NSAlert at vault open

#### Decisions Made
- **`pendingVaultRoot` companion to `pendingOperation`** — the working tree's `stage(_:vaultRoot:)` shape (uncommitted but landed) means the diff sheet now reads vault root from the controller. Phase 3 mirrors that with both `pendingOperation` and `pendingVaultRoot`, so `presentPending()` just copies the pair onto the staged slot via `stage()`.
- **Auto-Review must be silent on every failure mode** — original spec routed through `beginSession`, which pops an `NSAlert` if `claude` isn't found. That would NSAlert every vault open. Inlined the runner check in `runReviewIfStale` and gated the catch-block `presentError` by `stageMode` so neither missing-CLI nor agent failures interrupt the user at vault-open time.
- **Idempotency guard** — `runReviewIfStale` bails if `controller.hasPendingReview || isPresenting || isRunningRecipe`. Prevents double-fire when both `.onAppear` and `onChange(activeLocation?.id)` fire on first window open, and prevents stomping a Review the user is currently looking at.
- **Pre-existing AGENTS.md drift left as separate cleanup** — `Shared/Resources/wiki-template/AGENTS.md:34` still says `Lint (⌃⌘L)`. Now doubly wrong (wrong name AND wrong shortcut). PROGRESS.md already flags this as a separate naming-drift cleanup pass; not bundled into Phase 3.

#### Blockers
- (none)

---

### Phase 4: Codex CLI runner + Settings → Wiki tab
**Status:** Completed (awaiting manual verification)
**Commit scope:** `[mac]`

#### Tasks
**A. New runner**
- [x] Create `Clearly/Wiki/CodexCLIAgentRunner.swift` conforming to `AgentRunner`
- [x] Subprocess: `codex exec --json --skip-git-repo-check --sandbox read-only --ephemeral --output-last-message <tmpfile> [--model <m>] -`
- [x] Parse JSONL stdout for `turn.completed.usage.{input_tokens, cached_input_tokens, output_tokens}`; read final message from tmpfile
- [x] `AgentDiscovery.codexCandidatePaths` now probes `~/.codex/bin/codex`, `~/.local/bin/codex`, `/usr/local/bin/codex`, `/opt/homebrew/bin/codex` + `which codex`

**B. Runner preference resolver**
- [x] `WikiAgentCoordinator.swift` `resolveToolEnabledRunner(vaultURL:)`: reads `UserDefaults.standard.string(forKey: "wikiAgentRunner") ?? "auto"`, routes to Claude / Codex / auto-fallback
- [x] `warmForActiveVaultIfPossible(workspace:)` now delegates to `resolveToolEnabledRunner` so the picker affects warmup too
- [x] Updated install-message error strings to mention both CLIs with both docs URLs; generalized `"Asking Claude…"` status text to `"Asking the agent…"`; replaced empty-state copy on Chat panel ("Claude reads your notes" → "The agent reads your notes")

**C. Settings tab**
- [x] Added `WikiSettingsTab` private struct at the bottom of `Clearly/SettingsView.swift`, matching the existing `SyncSettingsTab` pattern
- [x] Inserted into TabView between Command Line and About: `Label("Wiki", systemImage: "sparkles")`
- [x] Tab contents: Picker on `@AppStorage("wikiAgentRunner")` with auto/claude/codex tags + caption; Detection section with Claude Code + Codex CLI rows showing resolved path or "Not detected" + install link. Refresh on `.onAppear` and `NSApplication.didBecomeActiveNotification`.

**D. Refactor**
- [x] Extracted `ProcessCaptureState` from inside `ClaudeCLIAgentRunner.swift` into its own `Clearly/Wiki/ProcessCaptureState.swift` (internal access). Both runners share the same three-stream resume-once-on-completion helper.

**Verify**
- [x] `xcodegen generate` clean
- [x] `xcodebuild Debug build` clean
- [x] `swift test` clean (93/93)
- [ ] Manual: Settings → Wiki tab renders, detection state correct
- [ ] Manual: with both CLIs → switch preference, verify right binary runs (Activity Monitor / DiagnosticLog)
- [ ] Manual: with only Claude / only Codex / neither — correct fallback behavior
- [ ] Manual: Codex Chat round-trip works; second call within ~5min shows non-zero `cached_input_tokens`

#### Decisions Made
- **Single source of truth for runner resolution** — `warmForActiveVaultIfPossible` previously inlined `findClaude` + `ClaudeCLIAgentRunner.init`; refactored to delegate to `resolveToolEnabledRunner` so the user's picker selection always wins, including warmups. One function owns runner choice.
- **`ProcessCaptureState` extraction** — both runners need the identical three-async-readers + resume-once helper. Extracting to its own file with `internal` access avoids duplication and keeps the runner files focused on their own argument shape and output parsing.
- **Codex `Usage` not surfaced through `AgentResult`** — `AgentResult` only carries `inputTokens` / `outputTokens`. `cached_input_tokens` is logged via `DiagnosticLog` (matches the IMPLEMENTATION.md success criterion of "non-zero `cached_input_tokens` in DiagnosticLog after a second call within ~5 min") but not added to the public struct shape. Keeps the protocol contract identical to Claude.
- **Generic empty-state copy on Chat panel** — `WikiChatView.swift:146` previously read "Claude reads your notes…"; rewritten to "The agent reads your notes…" because the user can now switch to Codex.
- **Internal doc comments mentioning Claude left as-is** — `AgentWarmer`'s 5-min cache-TTL comment is Claude-specific (Codex caching behavior is unverified at the time of writing), so the comment is accurate historical context, not user-facing copy. No reason to rewrite.

#### Blockers
- (none)

---

### Phase 5: Native semantic search via NLContextualEmbedding + MCP
**Status:** Completed (awaiting manual verification)
**Commit scope:** `[shared]`

#### Tasks
**A. Embedding service**
- [x] Create `Packages/ClearlyCore/Sources/ClearlyCore/Vault/EmbeddingService.swift` wrapping `NLContextualEmbedding(language: .english)`
- [x] Implement `embed(_ text: String) -> [Float]` (mean-pool per-token outputs; lazy asset-download via semaphore)
- [x] Implement `cosine(_ a: [Float], _ b: [Float]) -> Float` (zero-vector safe; no NaN)
- [x] Define `MODEL_VERSION` constant
- [x] `[Float].blobData` + `[Float].fromBlobData(_:)` round-trip helpers for SQLite BLOB storage
- [x] Tests (11 cases): identical text → cosine 1.0; whitespace variant → cosine ≥ 0.99; topical match outscores unrelated; orthogonal → 0; opposite → -1; zero-vector → 0 (not NaN); empty text throws; dimension matches model; BLOB round-trip exact; misaligned-size BLOB rejected

**B. GRDB schema migration**
- [x] `VaultIndex.swift`: `v2_embeddings` migration creates `embeddings(file_id PK FK→files.id ON DELETE CASCADE, content_hash, model_version, vector BLOB, updated_at)` + `idx_embeddings_model`
- [x] Public methods: `upsertEmbedding`, `embeddingsMissingOrStale`, `allEmbeddings`, `embedding(forFileID:)`, `deleteAllEmbeddings`
- [x] `scheduleEmbeddingRefresh(modelVersion:)` — cancellable background sweep that re-uses one `EmbeddingService` per pass; logs counts via `DiagnosticLog`; silent on every failure
- [x] Mac hook: `WorkspaceManager.reindexVault` calls `index.scheduleEmbeddingRefresh()` after `indexAllFiles`
- [x] iOS hook: `VaultSession.beginIndexing` (post-rebuild) and `scheduleIncrementalReindex` (post-update) both call `scheduleEmbeddingRefresh()`
- [x] Tests (9 cases): migration runs cleanly; upsert round-trip preserves vector exactly; cascade delete on file removal; missingOrStale surfaces new files / content_hash drift / model_version bump; allEmbeddings filters by model version; deleteAllEmbeddings clears table

**C. ClearlyCLI MCP tool**
- [x] Created `ClearlyCLI/Core/Tools/SemanticSearch.swift`: `semanticSearch(query:limit:vault:)` — embeds query, fetches all stored vectors at `MODEL_VERSION`, brute-force cosine, returns top-N with vault/path/filename/score/snippet
- [x] `snippetFor(absoluteURL:)` strips YAML frontmatter, takes first non-empty paragraph, truncates to ~200 chars
- [x] Registered `semantic_search` in `ToolRegistry.swift` with input/output schemas + `readAnnotations`
- [x] Dispatched in `Handlers.swift`
- [x] Updated `MCPCommand.swift` discussion text from "9 tools" → "10 tools"
- [x] Tests (4 new): `testListToolsReturnsAllRegisteredTools` confirms count=10; `testSemanticSearchRanksByCosineSimilarity` injects deterministic vectors and verifies sorted-by-score output; `testSemanticSearchSkipsEmbeddingsAtOtherModelVersions`; missing-query and zero-limit error paths

**D. In-app agent uses MCP (Claude AND Codex)**
- [x] Created `Clearly/Wiki/ClearlyMCPConfig.swift` with two consumers:
  - `claudeConfigFile(for:)` — writes `~/Library/Caches/wiki-agent/mcp.json`, returns URL for `--mcp-config <path>` + `--strict-mcp-config`
  - `codexInlineArgs(for:)` — returns `-c mcp_servers.clearly.command="..." -c mcp_servers.clearly.args=[...] -c mcp_servers.clearly.startup_timeout_sec=15` argv fragments. No file writes; user's `~/.codex/config.toml` untouched
- [x] `ClaudeCLIAgentRunner.swift`: kept `--tools "Read,Grep,Glob"` for built-in restriction (initially mistakenly replaced — caught + fixed in skeptical pass) and added `--allowedTools <mcp tool names>` to grant MCP invocation permission; appends `--mcp-config <path> --strict-mcp-config` when non-nil. Two new init params: `allowedMCPTools` and `mcpConfigPath`.
- [x] `CodexCLIAgentRunner.swift`: added `mcpInlineArgs` init param spliced after `exec` and before operational flags
- [x] `WikiAgentCoordinator.makeClaude` / `makeCodex` wire MCP config; both log `DiagnosticLog` warning if config build fails (degrades to Read/Grep/Glob — Claude Code ignores unknown `mcp__*` whitelist entries)

**E. Recipe prompts**
- [x] `Shared/Resources/recipes/chat.md`: prefer `mcp__clearly__semantic_search` for conceptual queries; Grep for proper nouns; `mcp__clearly__search_notes` for BM25-ranked relevance with snippets
- [x] `Shared/Resources/recipes/capture.md`: discover related notes via Grep / Glob / `mcp__clearly__semantic_search`
- [x] `Shared/Resources/recipes/review.md`: added bullet for spotting conceptual contradictions via `mcp__clearly__semantic_search`
- Did NOT touch `tool_allowlist:` frontmatter — currently doc-only at runtime; making it source-of-truth is a clean follow-up

**Verify (automated)**
- [x] `xcodegen generate` clean
- [x] `xcodebuild Debug build` clean (Mac app)
- [x] `swift test` ClearlyCore: 116/116 (was 93, +20 EmbeddingService + 9 VaultIndexEmbeddings, with prior tests intact)
- [x] `xcodebuild test` ClearlyCLIIntegrationTests: 30/30 (was 26, +4 semantic_search cases)
- [x] Bundled `Clearly Dev.app/Contents/Resources/recipes/{chat,capture,review}.md` carry the new prose

**Verify (manual — pending Josh)**
- [ ] Manual A (correctness): vault with `deep-work.md` (no "focus"/"productivity") + filler notes; Chat "notes about productivity" → DiagnosticLog shows `mcp__clearly__semantic_search` call; answer cites `[[deep-work]]`
- [ ] Manual B (regression): Karpathy gist Capture flow still works end-to-end
- [ ] Manual C (Codex parity): uninstall `claude`, ensure `codex` ≥ 0.120.0; same productivity query exercises `mcp__clearly__semantic_search` via Codex; `~/.codex/config.toml` byte-identical before/after
- [ ] Manual C2 (total degradation): both CLIs gone OR bundled CLI missing → silent fallback to Read/Grep/Glob, no NSAlert
- [ ] Manual D (performance): 500-note vault → `semantic_search` round-trip <100ms via DiagnosticLog timestamps; first-run reindex ~30s on Apple Silicon, no UI hang
- [ ] Manual E (schema durability): bump `EmbeddingService.MODEL_VERSION` to 2 in source, rebuild, reopen vault → catch-up sweep re-embeds every note (verify via `model_version=2` count in sqlite3)

#### Decisions Made
- **Schema FK is `file_id`, not `relative_path`** — IMPLEMENTATION.md spec said `relative_path` but the existing `files` table has INTEGER `id`. Using `file_id INTEGER PRIMARY KEY REFERENCES files(id) ON DELETE CASCADE` mirrors the FK style of every other related table (links, tags, headings) and lets cascade delete clear orphaned vectors automatically.
- **One unified embedding sweep, not a per-file queue** — IMPLEMENTATION.md sketched a serial DispatchQueue with embedding jobs scheduled per file change. Implemented as a single cancellable `Task.detached` that runs the existing `embeddingsMissingOrStale` query and processes all stale rows in one pass. Calling again cancels the prior task. Simpler, idempotent, no queue depth to monitor.
- **Closure delivers `[Double]`, not `[Float]`** — verified against the system `NaturalLanguage.swiftinterface`. Mean-pool accumulates Doubles for precision, converts to Float at the end before storage.
- **Sync `init` + lazy `prepareIfNeeded`** — `EmbeddingService.init` is cheap (just instantiates `NLContextualEmbedding`); the first `embed(_:)` call blocks (semaphore) on asset download + `load()`. Worker queue is OK with this; UI never sees the wait.
- **Codex MCP via `-c key=value` overrides, not file mutation** — research turned up `codex exec`'s `-c key=value` flag (codex-cli ≥ 0.120.0). Three `-c` overrides set `mcp_servers.clearly.{command,args,startup_timeout_sec}`. The user's `~/.codex/config.toml` is never touched. Older Codex versions silently ignore unknown keys → degrades to no-MCP. (Originally the plan was Claude-only; web research changed it.)
- **`--tools` and `--allowedTools` are NOT interchangeable** — the plan said "replace `--tools` with `--allowedTools`". That was wrong. Empirical test: `claude --print --allowedTools "Read,Grep,Glob"` happily ran Bash. `--tools` REPLACES the built-in surface; `--allowedTools` is a per-tool PERMISSION grant *required* for MCP-tool invocation. The runner now passes BOTH — `--tools "Read,Grep,Glob"` for restriction, `--allowedTools "mcp__clearly__semantic_search,mcp__clearly__search_notes"` to permit MCP calls. Documented inline in `ClaudeCLIAgentRunner` so this lesson doesn't get re-forgotten.
- **Per-vault MCP config filenames** — `mcp-<sha256-prefix>.json` instead of a single shared `mcp.json`. Prevents a race where switching the active vault while a Capture is in flight would overwrite the file being read by the in-flight Claude subprocess.
- **Codex tool allowlisting deferred** — Claude has `--allowedTools`, Codex doesn't have a per-spawn equivalent. Codex auto-enables every MCP tool; the recipe prompt does the steering. The bundled MCP server's write tools (`create_note`, `update_note`) are not invoked because the wiki agent's recipes always emit `wiki_operation` JSON proposals, not direct writes. Belt-and-suspenders `disabled_tools` is a follow-up if telemetry shows abuse.
- **Helper-text drift in `MCPCommand.swift`** — its discussion mentioned "9 Clearly tools" by name. Updated to "10 tools" with the new name in the list, so `clearly mcp --help` stays current.
- **Bundled CLI is always available — no setup required** — addressed Josh's pre-build clarification: in-app semantic search uses the binary at `Clearly.app/Contents/Resources/Helpers/ClearlyCLI` directly. The Settings → Command Line "Install CLI" button (which symlinks to `/usr/local/bin/clearly`) is a separate, optional feature for terminal/external-MCP-client use.

#### Blockers
- (none)

---

## Session Log

### 2026-04-25 — Planning complete
- Conducted research on 7 user feedback items raised during V1 manual testing of the wiki feature
- 4 items confirmed for build, 1 expanded into native semantic search (was originally "QMD support"), 2 deferred/dropped
- Approved plan saved to `~/.claude/plans/melodic-questing-blossom.md`
- Created `docs/wiki/RESEARCH.md`, `docs/wiki/IMPLEMENTATION.md`, `docs/wiki/PROGRESS.md`
- Ready to begin Phase 1

### 2026-04-25 — Phase 1 implementation
- Deleted `AnthropicAPIAgentRunner.swift`, `KeychainStore.swift`, `KeychainStoreTests.swift`
- Trimmed Anthropic-decode tests out of `AgentRunnerTests.swift`
- Stripped BYOK code paths from `WikiAgentCoordinator.swift`: `promptForAPIKey`, `promptSecret`, fallback paragraphs in error strings, Keychain branch in `resolveToolEnabledRunner`, `missingAPIKey` arm of `describe`
- Removed `case missingAPIKey` from `AgentError`
- Removed `Set Anthropic API Key…` menu item from `ClearlyApp.swift`
- `xcodebuild Debug` clean; `swift test` 88/88 pass (was 95)
- Final grep sweep clean across `Clearly/` and `Packages/`
- Committed as a single `[mac]` change. Awaiting Josh's manual verification before merging or starting Phase 2.

### 2026-04-25 — Phase 2 implementation
- Added `Shared/Resources/wiki-template/getting-started.md` with the approved sparse welcome content
- Inserted fifth `(src, dst)` tuple in `Clearly/WikiSeeding.swift` between `log.md` and `raw/README.md` so all top-level marker files group together before the nested `raw/` entry
- Caught & fixed pre-existing bug: Wiki → Chat was bound to ⌃⌘Q which is the macOS Lock Screen shortcut on Ventura+. Rebound to ⌃⌘A. Welcome content updated to match.
- `xcodegen generate` ran clean; `xcodebuild Debug build` clean; `swift test` 90/90 pass
- Verified `Clearly Dev.app/Contents/Resources/wiki-template/` ships all 5 files (AGENTS.md, getting-started.md, index.md, log.md, raw/)
- Initial commit: `bd2451ca [mac] Wiki: seed getting-started.md, rebind Chat ⌃⌘Q→⌃⌘A`

### 2026-04-25 — Phase 2 follow-ups (skeptical pass + Josh feedback)
- Skeptical review caught two stale `⌃⌘Q` references that survived the initial commit: `AGENTS.md:30` (user-facing template) and `WikiAgentCoordinator.startChat` doc-comment. Fixed in `3a261a71`.
- Per Josh: after `WikiSeeder.createNewWiki` registers a new vault, route `getting-started.md` through `WorkspaceManager.openFile` so it lands as the active document with the sidebar selection on it (new-location branch only — convert-in-place and re-pick-existing leave the user alone). `17577878`.
- Per Josh: expanded welcome content with two opening paragraphs framing the LLM-wiki concept and crediting Andrej Karpathy's gist, before the three-command list. `17577878`.
- Per Josh: added "Drop in your own notes" section between the three-command list and "How it works" — explains the drag-from-Finder / `⌘N` / `raw/` paths and what trade-offs you make by skipping Capture. `3f667905`.
- Phase 2 manual verification complete. Ready for Phase 3.

### Pre-existing follow-ups surfaced during Phase 2
- `Shared/Resources/wiki-template/AGENTS.md` still uses `Ingest` / `Query` / `Lint` as operation names (the codebase uses `capture` / `chat` / `review` everywhere). Pre-existing drift, not introduced by Phase 2. Worth a separate cleanup pass to align AGENTS.md with the actual menu and recipe naming. Phase 3 made this drift more conspicuous — `Lint (⌃⌘L)` is now also the wrong shortcut since auto-Review removed the manual binding.

### 2026-04-25 — Phase 3 implementation
- Created `Clearly/Wiki/WikiVaultState.swift` — `Codable` struct persisted at `<vault>/.clearly/state.json` (mirrors the `.clearly/recipes/` directory pattern from `WikiSeeding.seedRecipes`). `read` fails closed; `write` is best-effort with `DiagnosticLog` swallow.
- `WikiOperationController.swift`: added `pendingOperation`, `pendingVaultRoot`, `hasPendingReview`, `holdForReview(_:vaultRoot:)`, `presentPending()`. Pending state is independent from staged state; `dismiss()` records a handled Review cooldown when a staged Review is accepted/rejected.
- `WikiAgentCoordinator.swift`: `startReview` deleted; replaced with `runReviewIfStale` which gates on a 24h cooldown via `WikiVaultState.read`, bails silently when `claude` CLI is missing or another wiki op is active, and routes successful proposals to `controller.holdForReview` instead of `stage`. `runRecipe` gained a `stageMode: StageMode` parameter (`.immediate` keeps Capture/Chat behaviour; `.holdForReview` is auto-Review). Empty Review results record cooldown immediately; non-empty Review proposals record only after the user handles the staged diff. Failure path under `.holdForReview` skips `presentError` — no NSAlert at vault open.
- `MacDetailColumn.swift`: passed `controller: wikiController` into `WikiLogSidebar` constructor; added `runReviewIfStale` to `.onAppear`, `onChange(of: workspace.activeLocation?.id)`, and `onChange(of: workspace.treeRevision)`. Deleted the stale `.wikiReview` observer so the deleted `startReview` has zero references.
- `WikiLogSidebar.swift`: accepts `@Bindable var controller: WikiOperationController`. Header is now a `VStack` — when `controller.hasPendingReview`, a `pendingBadge` row sits above the existing `Log` row with a tinted dot, "Review ready · N change(s)" label, and chevron. Click → `controller.presentPending()`.
- `ClearlyApp.swift`: deleted `Review` button + ⌃⌘L shortcut from `WikiCommands`. `OperationKind.review` enum case kept (still used by auto-Review and log entries).
- `xcodegen generate` clean; `xcodebuild Debug build` clean; `swift test` 93/93 pass.

### 2026-04-25 — Phase 3 skeptical pass (`/but-for-real`)
Caught four issues in the first cut and fixed them:
1. **`dismiss()` was wiping pending Review** — cross-flow bug. User holds a Review badge, runs Capture, dismisses Capture sheet → held Review gone. Same path via `accept` (which calls `dismiss` internally). Fix: pending state has its own lifecycle independent of staged; `dismiss` only clears staged. `presentPending` is the only path that clears pending.
2. **Race in `runReviewIfStale`** — synchronous double-call (`.onAppear` + `.onChange` both passing the synchronous guards before either Task body runs) double-fires the agent. Fix: re-check `controller.isRunningRecipe` inside the Task body. `runRecipe` sets the flag synchronously at its top, so the second Task to start sees it and bails.
3. **Dead code: `.wikiReview` Notification.Name + observer** — after deleting the menu item, nothing posts `.wikiReview`. Observer in `MacDetailColumn` was unreachable. Deleted both the declaration in `NativeShellSupport.swift` and the observer.
4. **Dead code: `promptText` helper** — only used by the deleted `startReview`. Deleted.

Build + tests still clean (93/93).

### 2026-04-25 — Review-fix pass
- Fixed delayed wiki detection: `MacDetailColumn` now retries auto-Review on `workspace.treeRevision`, so a vault that flips from `.regular` to `.wiki` after async tree loading still fires Review.
- Fixed cooldown durability bug: non-empty held Reviews no longer write `lastReviewAt` while the proposal is only in memory. The timestamp records when the user opens and accepts/rejects the staged Review; empty Review results still record immediately.
- Fixed rollback cleanup: `WikiOperationApplier` tracks directories created for `.create` changes and removes them during rollback. Added `testRollbackRemovesDirectoriesCreatedForCreate`.

### Known limitations (out of Phase 3 scope)
- **Held Review is in-memory** — `WikiOperationController` is `@State` in `MacRootView`; quitting Clearly without clicking the badge loses the held proposal. The cooldown no longer records until the Review is handled, so the next launch can re-run Review instead of silently suppressing it. Persisting `pendingOperation` to disk would avoid the rerun; out of scope here.
- **No manual escape hatch** — Review menu deleted; no UI to force a re-Review before the 24h cooldown expires. Acceptable per the plan.

Awaiting Josh's manual verification before merging or starting Phase 4.

### 2026-04-25 — Phase 5 skeptical pass (`/but-for-real`)
Caught five real issues by actually running `claude --print` against the bundled MCP server:

1. **`--allowedTools` doesn't restrict the built-in tool set.** I'd swapped `--tools "Read,Grep,Glob"` → `--allowedTools "Read,Grep,Glob,..."` thinking the new flag did both jobs. Empirical test: `claude --print --allowedTools "Read,Grep,Glob"` happily ran Bash and got `hi from bash`. The two flags are NOT interchangeable: `--tools` REPLACES the built-in surface; `--allowedTools` is a per-tool PERMISSION grant (and is *required* for MCP tools — without it, the agent gets `permission_denials` for `mcp__clearly__semantic_search`). Restored `--tools "Read,Grep,Glob"` and added `--allowedTools "mcp__clearly__semantic_search,mcp__clearly__search_notes"` alongside. Verified: Bash blocked, MCP callable, no denials.
2. **`mcp.json` was a single shared file across vaults.** All vaults wrote to `~/Library/Caches/wiki-agent/mcp.json` with their own path. If two warmups raced (vault switch while Capture is running), the second overwrites the first and the in-flight Claude subprocess reads the wrong vault path. Switched to `mcp-<sha256-prefix(8)>.json` keyed on the vault path.
3. **`semantic_search` filename kept the `.md` extension.** `search_notes` returns extension-stripped filenames (`deep-work` not `deep-work.md`). Switched `semantic_search` to match for wiki-link-friendly output.
4. **Snippet frontmatter detection broke on CRLF.** `lines.first == "---"` fails when the line is `"---\r"`. Now normalizes CRLF/CR to LF before splitting and tolerates leading-whitespace closing fences.
5. **`scheduleEmbeddingRefresh` task ordering.** Created the new `Task.detached` BEFORE cancelling the old one — both could run briefly. Now cancels first, then creates, both under the lock.

Build still clean; ClearlyCore 116/116; ClearlyCLIIntegrationTests 30/30. End-to-end Claude smoke confirmed with the corrected argv:
- `claude --print --tools "Read,Grep,Glob" --allowedTools "mcp__clearly__semantic_search,mcp__clearly__search_notes" --mcp-config <path> --strict-mcp-config` → MCP tool invocable, Bash blocked, no permission_denials.

### 2026-04-25 — Phase 5 implementation
- Created `EmbeddingService.swift` wrapping `NLContextualEmbedding(language: .english)` with mean-pooling, cosine, and BLOB round-trip helpers. 11 tests pass; 7 of them exercise the live model on this Mac.
- Added `v2_embeddings` migration to `VaultIndex.swift`, plus 5 public methods (`upsertEmbedding`, `embeddingsMissingOrStale`, `allEmbeddings`, `embedding(forFileID:)`, `deleteAllEmbeddings`) and `scheduleEmbeddingRefresh` — a cancellable `Task.detached` that runs the existing `missingOrStale` query and embeds each result silently. 9 schema/storage tests pass.
- Wired the catch-up sweep into both indexing paths: Mac via `WorkspaceManager.reindexVault`, iOS via `VaultSession.beginIndexing` (post-rebuild) and `scheduleIncrementalReindex` (post-update). Calling again cancels any in-flight sweep, so back-to-back FSEvents bursts don't pile up duplicate work.
- Created `ClearlyCLI/Core/Tools/SemanticSearch.swift` mirroring `SearchNotes.swift`. Brute-force cosine over `allEmbeddings(modelVersion:)`. Snippet helper strips YAML frontmatter, takes first non-empty paragraph, truncates to ~200 chars. Registered in `ToolRegistry.swift`, dispatched in `Handlers.swift`, MCPCommand discussion text updated from "9 tools" → "10 tools".
- Created `Clearly/Wiki/ClearlyMCPConfig.swift` exposing `claudeConfigFile(for:)` (writes JSON; consumed by `--mcp-config`+`--strict-mcp-config`) and `codexInlineArgs(for:)` (returns `-c mcp_servers.clearly.*` argv fragments — no file mutation, user's `~/.codex/config.toml` untouched).
- `ClaudeCLIAgentRunner.swift`: replaced `--tools` with `--allowedTools` (verified via `claude --help`); added `mcpConfigPath` init param. `CodexCLIAgentRunner.swift`: added `mcpInlineArgs` init param spliced after `exec`. `WikiAgentCoordinator.makeClaude/makeCodex` wire MCP config; both log `DiagnosticLog` warning if config build fails (degrades to Read/Grep/Glob).
- Updated `chat.md`, `capture.md`, `review.md` recipe prose to mention `mcp__clearly__semantic_search` (and `mcp__clearly__search_notes` for chat). Did not touch `tool_allowlist:` frontmatter — currently doc-only at runtime.
- Added 4 integration tests for `semantic_search` + raised `testListToolsReturnsAllRegisteredTools` count to 10. ClearlyCore: 116/116 pass; ClearlyCLIIntegrationTests: 30/30 pass; `xcodebuild -scheme Clearly -configuration Debug build` clean.
- Bundled `Clearly Dev.app/Contents/Resources/recipes/{chat,capture,review}.md` carry the new prose (verified after a clean build).
- Awaiting Josh's manual verification (vault correctness, Codex parity, performance, MODEL_VERSION durability) before merging.

### 2026-04-25 — Phase 4 implementation
- Created `Clearly/Wiki/CodexCLIAgentRunner.swift` (struct conforming to `AgentRunner`). Spawns `codex exec --json --skip-git-repo-check --sandbox read-only --ephemeral --output-last-message <tmpfile> [--model <m>] -` with the prompt on stdin; parses JSONL `turn.completed` for usage; reads the final assistant message from the tmpfile (deleted via `defer`). Logs `cached_input_tokens` through `DiagnosticLog` for cache-hit verification. Returns `AgentResult` with `model: "codex-cli"`.
- Extracted the shared three-stream coordinator `ProcessCaptureState` from `ClaudeCLIAgentRunner.swift` into `Clearly/Wiki/ProcessCaptureState.swift` with `internal` access so both runners can share it.
- Added `~/.codex/bin/codex` to `AgentDiscovery.codexCandidatePaths` (the canonical install location for the official `@openai/codex` npm package).
- `WikiAgentCoordinator.resolveToolEnabledRunner(vaultURL:)` now reads `UserDefaults.standard.string(forKey: "wikiAgentRunner") ?? "auto"` and routes through `makeClaude` / `makeCodex` helpers. `warmForActiveVaultIfPossible(workspace:)` delegates to the same resolver, so the picker preference applies to cache warmups as well.
- Generalized install-error strings ("Install Claude Code or Codex CLI…" with both docs URLs), the auto-Review skip message ("no agent CLI installed"), the recipe status text ("Asking the agent…"), and the empty-state copy on the Chat panel.
- Inserted `WikiSettingsTab` (private struct) at the bottom of `Clearly/SettingsView.swift` and added it to the TabView between Command Line and About: `Label("Wiki", systemImage: "sparkles")`. Tab is a `Form` with two sections — Agent (Picker on `@AppStorage("wikiAgentRunner")` plus a caption) and Detection (rows for Claude Code / Codex CLI showing resolved path with green checkmark or "Not detected" + install link). Refreshes on `.onAppear` and `NSApplication.didBecomeActiveNotification`, matching the Command Line tab's pattern.
- `xcodegen generate` clean; `xcodebuild Debug build` clean; `swift test` 93/93 pass.

---

## Files Changed
(Will be updated as implementation progresses)

## Architectural Decisions
(Will be updated as implementation progresses; see RESEARCH.md for the decisions made during planning)

- **CLI is the only agent backend** — drops the Anthropic API path entirely; subscription auth via `claude` / `codex` CLIs is sufficient
- **Recipes are app behavior, not user content** — vault-local recipe customization stays disabled; recipe versioning concept dropped
- **Semantic search is native, not external** — `NLContextualEmbedding` (zero bundle weight) + brute-force cosine in Swift; `sqlite-vec` deferred until vaults exceed ~50K notes
- **One MCP server, two consumers** — same `semantic_search` MCP tool serves both external agents (Claude Desktop) via existing Settings copy-MCP-config flow AND in-app wiki agent via `--mcp-config` + `--strict-mcp-config`

## Lessons Learned
(Will be updated as implementation progresses)
