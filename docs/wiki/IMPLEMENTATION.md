# Wiki feature implementation plan

**Branch**: `llm-wiki-exploration`
**Research**: `docs/wiki/RESEARCH.md`
**Source plan**: `~/.claude/plans/melodic-questing-blossom.md` (approved)

## Overview

V1.5 of the wiki feature: convert the seven follow-ups raised during V1 manual testing into shippable changes. Five items get built; two are explicitly deferred or rejected (see RESEARCH.md). Each phase below ships as one `[mac]` or `[shared]` commit and produces a user-testable result.

## Prerequisites

- Branch `llm-wiki-exploration` checked out
- `claude` CLI installed locally (the runner being verified across all phases)
- `xcodegen` available (every phase that adds/removes files re-runs it)
- macOS 15+ build target (Item 5 needs `NLContextualEmbedding` which is macOS 14+; we ship 15+)
- `Codex` CLI installed for Phase 4 verification (optional; phase ships either way)

## Phase summary

| Phase | Title | Scope | Commit |
|---|---|---|---|
| 1 | Drop the Anthropic API-key path | Delete BYOK runner + KeychainStore + menu item; tighten error messages | `[mac]` |
| 2 | Seed `getting-started.md` on wiki creation | One template file + one entry in `WikiSeeder.seed` | `[mac]` |
| 3 | Auto-Review on vault open with sidebar badge | Per-vault state file + controller `holdForReview` + LogSidebar badge UI; remove menu item | `[mac]` |
| 4 | Codex CLI runner + Settings → Wiki tab | New `CodexCLIAgentRunner`, runner-preference resolver, Settings UI | `[mac]` |
| 5 | Native semantic search via `NLContextualEmbedding` + MCP | Embedding service, GRDB schema, ClearlyCLI MCP tool, in-app agent uses `--mcp-config` | `[shared]` |

Each phase is independently mergeable. Phases 1–4 are pure Mac changes; Phase 5 touches `ClearlyCore` and `ClearlyCLI`.

---

## Phase 1: Drop the Anthropic API-key path

### Objective
Remove every code path that prompts for, stores, or falls back to an Anthropic API key. CLI runners are the only supported agent backend.

### Rationale
First because every other phase touches `WikiAgentCoordinator.swift` — getting the resolver simplified up front means later phases edit a smaller, cleaner function. Also reduces surface area before Phase 4 layers a runner-preference picker on top.

### Tasks
- [ ] Delete `Packages/ClearlyCore/Sources/ClearlyCore/Wiki/AnthropicAPIAgentRunner.swift`
- [ ] Delete `Packages/ClearlyCore/Sources/ClearlyCore/Wiki/KeychainStore.swift`
- [ ] In `Clearly/Wiki/WikiAgentCoordinator.swift`:
  - [ ] Remove `promptForAPIKey()` (lines 208–221)
  - [ ] Remove `promptSecret(...)` (lines 454–466)
  - [ ] Rewrite `resolveToolEnabledRunner(vaultURL:)` (lines 328–342) to return only a CLI-backed `AgentRunner?` — `nil` when no CLI is found
  - [ ] Update error strings at lines 84–89 and 238–244 to drop the BYOK fallback line; replace with `"Install Claude Code to use this command. https://docs.claude.com/claude-code"` (Phase 4 will expand this once Codex is added)
- [ ] In `Clearly/ClearlyApp.swift` lines 1073–1076: remove the `Set Anthropic API Key…` menu item
- [ ] Run `xcodegen generate` (file deletions need it per CLAUDE.md)

### Success criteria
- `xcodebuild -scheme Clearly -configuration Debug build` clean
- `cd Packages/ClearlyCore && swift test` clean (95+ tests)
- `grep -r "anthropicAPIKey\|AnthropicAPIAgentRunner\|KeychainStore\|promptForAPIKey\|promptSecret\|Set Anthropic API Key" Clearly/ Packages/ClearlyCore/` returns no hits
- Manual: with `claude` CLI installed → Chat works as before. Without `claude` (rename the binary temporarily) → Chat surfaces the install message, no key prompt.

### Files likely affected
- `Packages/ClearlyCore/Sources/ClearlyCore/Wiki/AnthropicAPIAgentRunner.swift` (delete)
- `Packages/ClearlyCore/Sources/ClearlyCore/Wiki/KeychainStore.swift` (delete)
- `Clearly/Wiki/WikiAgentCoordinator.swift`
- `Clearly/ClearlyApp.swift`
- `project.yml` (regenerated)

---

## Phase 2: Seed `getting-started.md` on wiki creation

### Objective
Every newly-created (or converted) wiki vault gets a `getting-started.md` welcome note seeded next to `AGENTS.md` / `index.md` / `log.md`.

### Rationale
Smallest discrete user-facing improvement. Drops in cleanly with no architectural risk; gets a user-visible win shipped while Phase 3 (the larger UX restructure) is in flight.

### Tasks
- [ ] Create `Clearly/Resources/wiki-template/getting-started.md` with the welcome content (sparse, three-command focused — see plan file or RESEARCH.md for draft text)
- [ ] In `Clearly/WikiSeeding.swift` lines 27–36: add a fifth `(src, dst)` entry for `getting-started.md`. Existing skip-if-exists guard at line 49 keeps Convert-to-LLM-Wiki safe (won't overwrite an existing file)
- [ ] Run `xcodegen generate` (resource bundle path picks up the new file via existing globs but per CLAUDE.md run anyway)

### Success criteria
- `xcodebuild` clean
- `swift test` clean
- Manual: File → New LLM Wiki → folder gets 5 files including `getting-started.md`. Opening the new vault, the welcome note is among the visible files in the sidebar.
- Manual: Convert-to-LLM-Wiki on a folder that already contains `getting-started.md` leaves the existing file untouched.

### Files likely affected
- `Clearly/Resources/wiki-template/getting-started.md` (new)
- `Clearly/WikiSeeding.swift`
- `project.yml` (regenerated)

---

## Phase 3: Auto-Review on vault open with sidebar badge

### Objective
Replace the explicit `Wiki → Review` menu item with a quiet auto-Review that fires on vault open if >24h has elapsed since the last run. Pending changes surface as a subtle badge in the LogSidebar header; clicking opens the diff sheet.

### Rationale
Three coordinated pieces (state file + controller refactor + badge UI) but they're tightly coupled — splitting them would leave broken intermediate states. The hardest piece is the `holdForReview` tweak to the controller, which has to land alongside the trigger that uses it.

### Tasks
**A. Per-vault state**
- [ ] Create `Clearly/Wiki/WikiVaultState.swift` defining `WikiVaultState` (`Codable` struct with `lastReviewAt: Date?` and `schemaVersion: Int = 1`), plus `read(at:)` and `recordReviewRun(at:)` static helpers
- [ ] State file location: `<vault>/.clearly/state.json`. Read fails closed (returns `nil` → treat as stale). Write is best-effort; failures log via `DiagnosticLog` and swallow

**B. Controller `holdForReview`**
- [ ] In `Clearly/Wiki/WikiOperationController.swift`:
  - [ ] Add `var pendingOperation: WikiOperation?`
  - [ ] Add computed `var hasPendingReview: Bool { pendingOperation != nil }`
  - [ ] Add `func holdForReview(_ operation: WikiOperation)` — sets `pendingOperation`
  - [ ] Add `func presentPending()` — moves `pendingOperation` → `stagedOperation` via existing `stage()`
  - [ ] Update `dismiss()` to also clear `pendingOperation`

**C. Trigger + integration**
- [ ] In `Clearly/Wiki/WikiAgentCoordinator.swift`:
  - [ ] Replace `startReview(workspace:controller:)` (lines 165–188) with `runReviewIfStale(workspace:controller:)` — drops the focus prompt; auto-Review is unscoped (general pass)
  - [ ] Function logic: bail unless wiki vault active; check `WikiVaultState.read(at:)`, return if `lastReviewAt < 24h ago`; run Review via existing `runRecipe(...)` pipeline but route success to `controller.holdForReview(op)` instead of `stage(op)`; always `recordReviewRun` on success (including empty changes); on failure log + don't record
- [ ] In `Clearly/Native/MacDetailColumn.swift` lines 221–222: extend the existing `onChange(of: workspace.activeLocation?.id)` block to also call `WikiAgentCoordinator.runReviewIfStale(...)`

**D. Badge UI**
- [ ] In `Clearly/Wiki/WikiLogSidebar.swift`: add a header affordance that's only visible when `wikiController.hasPendingReview`. Show a small filled circle + a clickable "Review ready · N changes" link. Click → `wikiController.presentPending()`
- [ ] (Optional polish) On the Wiki menu's "Toggle Log Sidebar" item, add a subtle dot when pending. Skip if it complicates the menu rendering

**E. Remove the Review menu item**
- [ ] In `Clearly/ClearlyApp.swift` lines 1057–1061: delete the `Review` button + ⌃⌘L shortcut. Keep the `.wikiReview` notification name (still used by the Debug "Preview Diff Sheet" path) and `OperationKind.review` enum case (used by log entries)

### Success criteria
- `xcodebuild` clean
- `swift test` clean
- Manual flow A: New wiki, write `<vault>/.clearly/state.json` with `lastReviewAt` set 25h ago, close & reopen workspace → Review fires silently in background. If it proposes changes, badge appears in LogSidebar header. Click badge → diff sheet opens with the held op.
- Manual flow B: Same vault, close & reopen within 24h → no fire (verify via DiagnosticLog: should log "[Review] skipped: ran X minutes ago" or similar)
- Manual: Wiki menu has no `Review` item; Toggle Log Sidebar (⌃⌘T) still works
- Manual: Empty Review result still records timestamp (won't re-fire next launch)

### Files likely affected
- `Clearly/Wiki/WikiVaultState.swift` (new)
- `Clearly/Wiki/WikiOperationController.swift`
- `Clearly/Wiki/WikiAgentCoordinator.swift`
- `Clearly/Wiki/WikiLogSidebar.swift`
- `Clearly/Native/MacDetailColumn.swift`
- `Clearly/ClearlyApp.swift`
- `project.yml` (regenerated)

---

## Phase 4: Codex CLI runner + Settings → Wiki tab

### Objective
Add `Codex` CLI as a selectable alternative to `Claude` Code. New Settings → Wiki tab exposes a runner picker (`auto | claude | codex`); auto prefers Claude, falls back to Codex.

### Rationale
Self-contained: one new runner, one resolver tweak, one Settings tab. Doesn't touch any code Phase 5 will edit. Ships a visible Settings surface that's also the natural home for any future wiki preferences.

### Tasks
**A. New runner**
- [ ] Create `Clearly/Wiki/CodexCLIAgentRunner.swift` conforming to `AgentRunner` (`Packages/ClearlyCore/Sources/ClearlyCore/Wiki/AgentRunner.swift:7-9`). Subprocess shape:
  ```
  codex exec --json --skip-git-repo-check --sandbox read-only --ephemeral \
             --output-last-message <tmpfile> [--model <m>] -
  ```
  Prompt fed via stdin. Final assistant message read from `<tmpfile>`. JSONL parsing of stdout to extract `turn.completed.usage.{input_tokens, cached_input_tokens, output_tokens}`. Return `AgentResult` matching the existing shape.
- [ ] Use `AgentDiscovery.findCodex()` (existing stub at `Clearly/Wiki/AgentDiscovery.swift:17-19`) — verify probe paths cover `~/.codex/bin/codex`, `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, `which codex`. Complete the stub if needed.

**B. Runner preference resolver**
- [ ] Update `Clearly/Wiki/WikiAgentCoordinator.swift` `resolveToolEnabledRunner(vaultURL:)`:
  ```swift
  let pref = UserDefaults.standard.string(forKey: "wikiAgentRunner") ?? "auto"
  // ... see plan file for full body — reads pref, makes Claude / Codex runner based on pref + availability
  ```
- [ ] Apply the same preference inside `warmForActiveVaultIfPossible(workspace:)` (lines 194–206) so cache warm-up uses the active runner
- [ ] Update install-message error strings (from Phase 1) to mention both: `"Install Claude Code or Codex CLI to use this command."` with both docs URLs

**C. Settings tab**
- [ ] Add `WikiSettingsTab` struct (inline in `Clearly/SettingsView.swift` or sibling file `Clearly/WikiSettingsTab.swift` — match existing `SyncSettingsTab` pattern)
- [ ] Add to TabView between Command Line and About (lines 23–43): `Label("Wiki", systemImage: "sparkles")`
- [ ] Tab contents:
  - Runner picker (`@AppStorage("wikiAgentRunner")` ∈ `auto | claude | codex`)
  - Detection rows: "Claude Code" with checkmark + path or X + "Not detected" + a `Help me install` link to `https://docs.claude.com/claude-code`. Same shape for "Codex CLI" linking to `https://developers.openai.com/codex/cli`
  - Caption under picker: "Auto picks Claude if installed, then Codex. Both runners use read-only file tools — they propose changes, you review the diff."

### Success criteria
- `xcodebuild` clean
- `swift test` clean (new tests for `CodexCLIAgentRunner` JSONL parsing if practical)
- Manual: Settings → Wiki tab renders, shows current detection state correctly (probe both binaries; flip a binary's executable bit to simulate "not detected")
- Manual: with both CLIs installed → switch preference, send a Chat message, verify the right binary runs (check Activity Monitor or `DiagnosticLog`)
- Manual: with only Claude → Auto picks Claude. With only Codex → Auto picks Codex. With neither → install message in Capture/Chat
- Manual: Codex Chat round-trip works end-to-end on a small wiki — answer renders; token usage shows up in DiagnosticLog with non-zero `cached_input_tokens` after a second call within ~5 min

### Files likely affected
- `Clearly/Wiki/CodexCLIAgentRunner.swift` (new)
- `Clearly/Wiki/AgentDiscovery.swift` (verify/complete)
- `Clearly/Wiki/WikiAgentCoordinator.swift`
- `Clearly/SettingsView.swift` (or new `Clearly/WikiSettingsTab.swift`)
- `project.yml` (regenerated)

---

## Phase 5: Native semantic search via `NLContextualEmbedding` + MCP

### Objective
Build native semantic search into Clearly. Embeddings via Apple's `NLContextualEmbedding`, stored as `Float32` BLOBs in the existing GRDB schema, queried via brute-force cosine in Swift. Exposed as a `semantic_search` MCP tool that **both** the in-app wiki agent AND external agents (Claude Desktop, etc.) consume via the existing ClearlyCLI MCP server.

### Rationale
Largest phase by far — lands last so the simpler items are already shipped and verified. Touches ClearlyCore (`VaultIndex` schema), ClearlyCLI (new MCP tool), and the wiki agent runner (MCP wiring). Splits naturally into infrastructure (embedding + storage) and integration (MCP tool + agent uses it), but every sub-piece needs the others to be testable end-to-end — so it's one phase.

### Tasks
**A. Embedding service**
- [ ] Create `Packages/ClearlyCore/Sources/ClearlyCore/Vault/EmbeddingService.swift`:
  - `import NaturalLanguage`
  - Wrap `NLContextualEmbedding(language: .english)` (with a TODO for multilingual model selection later)
  - Generate embedding for a string: tokenize, run through model, mean-pool per-token outputs to a single `[Float]` vector
  - Provide `cosine(_ a: [Float], _ b: [Float]) -> Float`
  - `MODEL_VERSION` constant — bumping this forces a vault-wide reindex
- [ ] Tests in `Packages/ClearlyCore/Tests/ClearlyCoreTests/`:
  - Identical text → cosine 1.0
  - Same text different whitespace → cosine ≈1.0
  - Unrelated text → cosine < 0.5
  - Vector length matches expected dimensionality

**B. GRDB schema migration**
- [ ] In `Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultIndex.swift`: add a migration that creates the `embeddings` table:
  ```sql
  CREATE TABLE embeddings (
      relative_path TEXT PRIMARY KEY REFERENCES notes(relative_path) ON DELETE CASCADE,
      content_hash TEXT NOT NULL,
      model_version INTEGER NOT NULL,
      vector BLOB NOT NULL,
      updated_at INTEGER NOT NULL
  );
  ```
- [ ] Hook into the existing FSEvents-driven note-indexing path: when a note is added or modified, queue an embedding job on a serial background queue. Skip if `content_hash` matches stored value AND `model_version` matches `EmbeddingService.MODEL_VERSION`. Otherwise compute + upsert.
- [ ] First-run reindex: on `VaultIndex.open`, count notes missing embeddings and dispatch a background catch-up sweep. Silent (no UI); existing FSEvents indexing is silent too.

**C. ClearlyCLI MCP tool**
- [ ] Create `ClearlyCLI/Core/Tools/SemanticSearch.swift`: function `semanticSearch(query: String, limit: Int, vault: LoadedVault) -> [SearchHit]`. Compute query embedding, fetch all stored vectors from `embeddings` table for the vault, brute-force cosine similarity, return top-N. `SearchHit` struct: `relativePath`, `score`, `snippet` (first ~200 chars or first non-frontmatter paragraph)
- [ ] Register in `ClearlyCLI/MCP/ToolRegistry.swift`: tool name `semantic_search`, input schema `{query: string, limit?: int (default 10), vault?: string}`
- [ ] Dispatch in `ClearlyCLI/MCP/Handlers.swift`: route `semantic_search` to the new function, wrap return in `structuredCall<T: Encodable>()` like other tools
- [ ] CLI test: `clearly mcp` + tools/list shows `semantic_search`; tools/call returns ranked results for a synthetic query

**D. In-app agent uses MCP**
- [ ] Create `Clearly/Wiki/ClearlyMCPConfig.swift`: generates a per-spawn `mcp.json` file pointing at the bundled ClearlyCLI binary. Reuse `CLIInstaller.bundledBinaryURL()` for path resolution. Write to a stable scratch location (e.g., `~/Library/Caches/com.sabotage.clearly/wiki-agent/mcp.json`) — overwrite each spawn or app launch
- [ ] Update `Clearly/Wiki/ClaudeCLIAgentRunner.swift` to spawn:
  ```
  claude --print --output-format json \
    --mcp-config <path-to-mcp.json> \
    --strict-mcp-config \
    --allowedTools "Read,Grep,Glob,mcp__clearly__semantic_search,mcp__clearly__search_notes" \
    --no-session-persistence \
    --exclude-dynamic-system-prompt-sections \
    [--model <m>]
  ```
  (Replace existing `--tools "Read,Grep,Glob"` with the new `--allowedTools` flag and expanded list.)
- [ ] Optional: same MCP wiring for `CodexCLIAgentRunner.swift` if `codex exec` accepts `--mcp-config`. If not (verify in implementation), semantic search ships Claude-only and Codex falls back to Grep+Read — acceptable.

**E. Recipe prompts**
- [ ] Update `Shared/Resources/recipes/{capture,chat,review}.md` to mention the new tool. Suggested text: *"Prefer `mcp__clearly__semantic_search` for conceptual queries where you don't know the exact terms in the vault. Use `Grep` for proper nouns, exact phrases, and file-path-style targets. Read the top-ranked notes."* The agent picks per query.

### Success criteria
- `xcodebuild` clean
- `swift test` clean — new EmbeddingService tests pass; new semantic_search tests pass
- CLI: `clearly mcp` + `tools/list` shows `semantic_search`. `tools/call` with a synthetic query against a test vault returns ranked results.
- Manual A (correctness): create a wiki vault with `deep-work.md` (no occurrence of "focus" or "productivity") and 49 unrelated notes. Send Chat query "notes about productivity". Check DiagnosticLog → confirm agent called `mcp__clearly__semantic_search`. Verify the answer cites `deep-work.md`.
- Manual B (regression): the existing Karpathy-gist Capture flow still works end-to-end.
- Manual C (degradation): with `claude` CLI not installed but `codex` installed (and Codex MCP wiring not done yet), Chat still works using Codex + Grep+Read silently.
- Performance: in a 500-note vault, `semantic_search` returns in <100ms (verify via DiagnosticLog timestamps around the MCP call).

### Files likely affected
**Create:**
- `Packages/ClearlyCore/Sources/ClearlyCore/Vault/EmbeddingService.swift`
- `Packages/ClearlyCore/Tests/ClearlyCoreTests/EmbeddingServiceTests.swift`
- `ClearlyCLI/Core/Tools/SemanticSearch.swift`
- `Clearly/Wiki/ClearlyMCPConfig.swift`

**Edit:**
- `Packages/ClearlyCore/Sources/ClearlyCore/Vault/VaultIndex.swift`
- `ClearlyCLI/MCP/ToolRegistry.swift`
- `ClearlyCLI/MCP/Handlers.swift`
- `Clearly/Wiki/ClaudeCLIAgentRunner.swift`
- `Clearly/Wiki/CodexCLIAgentRunner.swift` (if Codex MCP wiring works)
- `Shared/Resources/recipes/capture.md`
- `Shared/Resources/recipes/chat.md`
- `Shared/Resources/recipes/review.md`
- `project.yml` (regenerated)

---

## Post-implementation

- [ ] Run full smoke pass against a real wiki vault — Capture (URL), Capture (pasted text), Chat (lexical), Chat (conceptual — exercises semantic), Review (force fire via state.json), runner switch in Settings
- [ ] Confirm `[mac]` and `[shared]` commit prefixes are correct on every commit (per CLAUDE.md release scope rules)
- [ ] No release notes update needed yet — this work is on `llm-wiki-exploration`; CHANGELOG entries land when the branch merges to `main`
- [ ] If the wiki feature is going to ship in the next release, add it to `CHANGELOG.md` under the next version's section

## Notes

### What's intentionally not in this plan
- **Wiki-specific operation MCP tools** (`list_orphans`, `propose_operation`, `get_log_entries`) — deferred. Phase 5 lays the MCP wiring; adding more tools is short follow-up.
- **QMD as a dependency** — rejected. Superseded by Phase 5's native semantic. See RESEARCH.md.
- **Recipe versioning** — dropped. Vault-local recipes remain disabled. Shorten the comment at `Clearly/Wiki/WikiAgentCoordinator.swift:347-353` during Phase 1 or 4 (whichever touches that function next) to remove the "future feature" framing.

### Phase ordering rationale
- 1 first: simplifies the resolver everyone else edits
- 2 second: smallest discrete win, low risk, no coupling
- 3 third: largest UX restructure of the existing flow, but doesn't touch the agent layer
- 4 fourth: extends the runner abstraction; uses the cleaner resolver from Phase 1
- 5 last: largest phase, touches ClearlyCore + ClearlyCLI + wiki layer, benefits from everything else being shipped & verified first

### When something doesn't work
Per CLAUDE.md "Always Works" rule: don't claim a phase is complete until the manual verification has actually been performed. Type-check + test pass is necessary but not sufficient. The diff sheet, badge UI, and Settings tab are all visual surfaces that need eyes.
