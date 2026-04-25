# Wiki feature progress

## Status: Phase 1 — Completed (pending manual verification); Phase 2 — Not Started

## Quick Reference
- Research: `docs/wiki/RESEARCH.md`
- Implementation: `docs/wiki/IMPLEMENTATION.md`
- Source plan: `~/.claude/plans/melodic-questing-blossom.md`
- Branch: `llm-wiki-exploration`

---

## Phase Progress

### Phase 1: Drop the Anthropic API-key path
**Status:** Completed (pending manual verification)
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
- [ ] Manual: with `claude` installed → Chat works. Without → install message, no key prompt. **(awaits Josh)**

#### Decisions Made
- Bundled `Packages/ClearlyCore/Package.resolved` cleanup into the `[mac]` commit. The `eventsource` pin removal is directly caused by deleting `AnthropicAPIAgentRunner` (its SSE transitive dep). Other pin removals (sparkle, keyboardshortcuts, swift-sdk, etc.) were stale entries that don't belong in the `ClearlyCore` package's resolve file — `swift test` rewrote the file to match the package's actual deps (`cmark-gfm`, `grdb.swift`).
- Per CLAUDE.md scope rule "pick the most-specific user-visible scope": even though deletions hit `Packages/ClearlyCore/`, the user-visible result (no more BYOK key UI) is Mac-only — iOS never exposed it. `[mac]` is correct.

#### Blockers
- (none)

---

### Phase 2: Seed `getting-started.md` on wiki creation
**Status:** Not Started
**Commit scope:** `[mac]`

#### Tasks
- [ ] Create `Clearly/Resources/wiki-template/getting-started.md` with welcome content (sparse, three-command focused)
- [ ] `WikiSeeding.swift` lines 27–36: add fifth `(src, dst)` entry for `getting-started.md`
- [ ] Run `xcodegen generate`
- [ ] Verify: `xcodebuild Debug build` clean
- [ ] Verify: `swift test` clean
- [ ] Manual: File → New LLM Wiki → folder gets 5 files including `getting-started.md`
- [ ] Manual: Convert-to-LLM-Wiki on existing folder doesn't overwrite an existing welcome note

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 3: Auto-Review on vault open with sidebar badge
**Status:** Not Started
**Commit scope:** `[mac]`

#### Tasks
**A. Per-vault state**
- [ ] Create `Clearly/Wiki/WikiVaultState.swift` (`Codable` struct + `read(at:)` and `recordReviewRun(at:)` helpers)
- [ ] State file location: `<vault>/.clearly/state.json`; read fails closed → returns `nil` → treated as stale

**B. Controller `holdForReview`**
- [ ] `WikiOperationController.swift`: add `pendingOperation`, `hasPendingReview`, `holdForReview(_:)`, `presentPending()`
- [ ] Update `dismiss()` to also clear `pendingOperation`

**C. Trigger + integration**
- [ ] `WikiAgentCoordinator.swift`: replace `startReview(workspace:controller:)` (lines 165–188) with `runReviewIfStale(workspace:controller:)` — drop focus prompt, route success to `holdForReview`
- [ ] `MacDetailColumn.swift` lines 221–222: extend `onChange(of: workspace.activeLocation?.id)` to call `runReviewIfStale`

**D. Badge UI**
- [ ] `WikiLogSidebar.swift`: add header affordance visible only when `hasPendingReview` — "Review ready · N changes" link → `presentPending()`
- [ ] (Optional polish) Subtle dot on Wiki menu's "Toggle Log Sidebar" item

**E. Remove Review menu item**
- [ ] `ClearlyApp.swift` lines 1057–1061: delete Review button + ⌃⌘L shortcut. Keep `.wikiReview` notification + `OperationKind.review` enum case

**Verify**
- [ ] `xcodebuild Debug build` clean
- [ ] `swift test` clean
- [ ] Manual A: force `lastReviewAt` 25h ago → Review fires silently, badge appears, click → diff sheet opens
- [ ] Manual B: reopen within 24h → no fire (DiagnosticLog confirms skip)
- [ ] Manual: Wiki menu has no Review item; ⌃⌘T still works
- [ ] Manual: empty Review result still records timestamp

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 4: Codex CLI runner + Settings → Wiki tab
**Status:** Not Started
**Commit scope:** `[mac]`

#### Tasks
**A. New runner**
- [ ] Create `Clearly/Wiki/CodexCLIAgentRunner.swift` conforming to `AgentRunner`
- [ ] Subprocess: `codex exec --json --skip-git-repo-check --sandbox read-only --ephemeral --output-last-message <tmpfile> [--model <m>] -`
- [ ] Parse JSONL stdout for `turn.completed.usage.{input_tokens, cached_input_tokens, output_tokens}`; read final message from tmpfile
- [ ] Verify `AgentDiscovery.findCodex()` (lines 17–19) probes `~/.codex/bin/codex`, `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, `which codex`

**B. Runner preference resolver**
- [ ] `WikiAgentCoordinator.swift` `resolveToolEnabledRunner(vaultURL:)`: read `@AppStorage("wikiAgentRunner")` ∈ `auto | claude | codex`, route accordingly
- [ ] Apply same preference in `warmForActiveVaultIfPossible(workspace:)` (lines 194–206)
- [ ] Update install-message error strings: "Install Claude Code or Codex CLI to use this command." with both docs URLs

**C. Settings tab**
- [ ] Add `WikiSettingsTab` (inline in `SettingsView.swift` or new sibling file)
- [ ] Add to TabView between Command Line and About: `Label("Wiki", systemImage: "sparkles")`
- [ ] Tab contents: runner picker, detection rows for Claude + Codex with install links, caption explaining auto behavior

**Verify**
- [ ] `xcodebuild Debug build` clean
- [ ] `swift test` clean
- [ ] Manual: Settings → Wiki tab renders, detection state correct
- [ ] Manual: with both CLIs → switch preference, verify right binary runs (Activity Monitor / DiagnosticLog)
- [ ] Manual: with only Claude / only Codex / neither — correct fallback behavior
- [ ] Manual: Codex Chat round-trip works; second call within ~5min shows non-zero `cached_input_tokens`

#### Decisions Made
- (none yet)

#### Blockers
- (none)

---

### Phase 5: Native semantic search via NLContextualEmbedding + MCP
**Status:** Not Started
**Commit scope:** `[shared]`

#### Tasks
**A. Embedding service**
- [ ] Create `Packages/ClearlyCore/Sources/ClearlyCore/Vault/EmbeddingService.swift` wrapping `NLContextualEmbedding(language: .english)`
- [ ] Implement `embed(_ text: String) -> [Float]` (mean-pool per-token outputs)
- [ ] Implement `cosine(_ a: [Float], _ b: [Float]) -> Float`
- [ ] Define `MODEL_VERSION` constant
- [ ] Tests: identical text → cosine 1.0; whitespace variant → cosine ≈1.0; unrelated → cosine < 0.5; vector dim correct

**B. GRDB schema migration**
- [ ] `VaultIndex.swift`: add migration for `embeddings` table (relative_path PK, content_hash, model_version, vector BLOB, updated_at)
- [ ] Hook into FSEvents-driven indexing: queue embedding job on serial background queue when content_hash or model_version differs
- [ ] First-run reindex: on `VaultIndex.open`, dispatch background catch-up sweep for notes missing embeddings

**C. ClearlyCLI MCP tool**
- [ ] Create `ClearlyCLI/Core/Tools/SemanticSearch.swift`: `semanticSearch(query:limit:vault:) -> [SearchHit]` (relativePath, score, snippet)
- [ ] Register `semantic_search` in `ClearlyCLI/MCP/ToolRegistry.swift` with input schema
- [ ] Dispatch in `ClearlyCLI/MCP/Handlers.swift`
- [ ] CLI test: `clearly mcp` + tools/list shows `semantic_search`; tools/call returns ranked results

**D. In-app agent uses MCP**
- [ ] Create `Clearly/Wiki/ClearlyMCPConfig.swift`: generates per-spawn `mcp.json` pointing at bundled ClearlyCLI binary (reuse `CLIInstaller.bundledBinaryURL()`)
- [ ] Update `ClaudeCLIAgentRunner.swift`: replace `--tools` with `--allowedTools "Read,Grep,Glob,mcp__clearly__semantic_search,mcp__clearly__search_notes"`; add `--mcp-config <path>` and `--strict-mcp-config`
- [ ] Optional: same MCP wiring in `CodexCLIAgentRunner.swift` if `codex exec` accepts `--mcp-config`. Otherwise document the limitation

**E. Recipe prompts**
- [ ] Update `Shared/Resources/recipes/{capture,chat,review}.md` to mention `mcp__clearly__semantic_search` for conceptual queries; Grep for proper nouns / exact phrases

**Verify**
- [ ] `xcodebuild Debug build` clean
- [ ] `swift test` clean (EmbeddingService + semantic_search tests pass)
- [ ] CLI: `clearly mcp` exposes `semantic_search`; tools/call returns correct ranked results on a test vault
- [ ] Manual A (correctness): vault with `deep-work.md` (no "focus"/"productivity") + 49 unrelated notes; Chat "notes about productivity" → DiagnosticLog shows `mcp__clearly__semantic_search` call; answer cites `deep-work.md`
- [ ] Manual B (regression): Karpathy gist Capture flow still works
- [ ] Manual C (degradation): `claude` not installed but `codex` installed → Chat still works via Codex + Grep+Read
- [ ] Performance: 500-note vault → `semantic_search` returns in <100ms (DiagnosticLog timestamps)

#### Decisions Made
- (none yet)

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
