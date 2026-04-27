# Wiki feature research

**Branch**: `llm-wiki-exploration`
**Implementation plan**: `~/.claude/plans/melodic-questing-blossom.md`
**Date**: 2026-04-25

This document captures the technical research and design decisions behind the wiki feature's V1.5 round of work — the 7 items raised by manual testing of the initial pipeline. The implementation plan is separate; this is the *why* behind it.

---

## 1. CLI is the only runner. Drop the BYOK API path.

### Decision
Delete `AnthropicAPIAgentRunner`, `KeychainStore`, the `Set Anthropic API Key…` menu item, and every fallback branch that prompts for or stores an API key. CLI runners (Claude Code today, Codex tomorrow) are the only supported path.

### Rationale
- During testing, the user never exercised the API path. CLI was always available and faster (subscription caching, larger system prompt budget).
- The fallback branched the resolver, branched the error messages, and added a Keychain dependency — all to support a code path no actual user touches.
- Subscription users (Claude Pro/Max, ChatGPT Plus/Pro) get the work for free under flat-rate. Adding API key support shifts cost onto the user with no UX upside.

### Reverse course condition
Re-add API support **only** when a real user asks. The code is in git history; recovery is a `git revert` + a single `resolveToolEnabledRunner` branch.

---

## 2. Welcome state: seeded `getting-started.md`, not an empty-state UI

### Decision
Seed `getting-started.md` into the vault on creation alongside `AGENTS.md` / `index.md` / `log.md`. No SwiftUI empty-state panel.

### Rationale
- A markdown file is editable, deletable, and shows up in the existing sidebar / preview / Quick Switcher exactly like any other note. Zero new UI surface.
- An empty-state SwiftUI panel would duplicate the welcome content in code while requiring its own design + dark mode + accessibility pass.
- The seeded file doubles as discoverable documentation: when the user inevitably greps their vault for "how do I capture," `getting-started.md` is the answer.

### Content shape
Sparse, three-command focused (Capture / Chat / Toggle Log Sidebar). Karpathy's premise is that the wiki *grows* — the seed should be a starting line, not an encyclopedia.

---

## 3. Auto-Review on vault open (>24h), subtle badge — not a menu item

### Decision
Remove the `Wiki → Review` menu item. Auto-fire Review when a wiki vault is opened *if* >24h has passed since the last run. Pending changes surface as a subtle badge in the LogSidebar header — clicking opens the diff sheet. No interruption.

### Rationale
- Manual Review was being invoked roughly never. The feature is valuable (orphan detection, contradiction-finding) but invisible without proactive surfacing.
- 24h cadence matches the natural rhythm of a personal knowledge base. Daily reviews are enough; per-edit reviews are noise.
- Auto-opening a diff sheet on every vault open is invasive — *especially* when the user is mid-task. Badge + click is the right deference.

### Per-vault state file
Persist `lastReviewAt` at `<vault>/.clearly/state.json`. Read fails closed (returns `nil` → treated as stale → triggers Review). On success (including empty result) write the timestamp; on failure leave it stale so the next open retries.

### Why a badge, not a notification
Notifications are an OS-level interruption. The user is already looking at their wiki when the badge appears — it lives where their attention already is. Deferred to wherever the LogSidebar header naturally has visual weight.

---

## 4. Codex CLI as a switchable runner

### Decision
Add `Clearly/Wiki/CodexCLIAgentRunner.swift` conforming to the existing `AgentRunner` protocol. Settings → Wiki tab exposes a runner picker (`auto | claude | codex`); auto prefers Claude, falls back to Codex.

### Codex CLI vs Claude CLI — operational deltas

Verified against `openai/codex` `0.125.0` (April 2026) and Anthropic's `claude` Code CLI:

| Aspect | Claude Code | Codex CLI |
|---|---|---|
| Invocation | `claude --print [flags]` | `codex exec [flags]` (subcommand-based) |
| Output format | Single JSON envelope `{result, usage, is_error}` | JSONL event stream (`turn.started`, `item.*`, `turn.completed`) |
| Final-message access | Parse from envelope | `--output-last-message <file>` writes it cleanly |
| Token usage | `usage.input_tokens` / `output_tokens` / `cache_read_input_tokens` | `turn.completed.usage.{input_tokens, cached_input_tokens, output_tokens}` |
| Tool whitelist | `--tools "Read,Grep,Glob"` (name-based) | `--sandbox read-only` (mode-based; allows shell, blocks writes) |
| Session persistence | `--no-session-persistence` | `--ephemeral` |
| Stdin convention | Prompt via stdin by default with `--print` | `codex exec -` reads stdin |
| Outside-git behavior | Works | Refuses without `--skip-git-repo-check` |
| Auth | `claude` subscription via `~/.claude/.credentials.json` or `ANTHROPIC_API_KEY` | `~/.codex/auth.json` ("Sign in with ChatGPT") or `OPENAI_API_KEY` |
| Model selection | `--model <id>` | `--model <id>` |
| MCP support | `--mcp-config <file>`, `--strict-mcp-config`, tool whitelist via `mcp__server__tool` syntax | Similar shape (verify in implementation) |
| Prompt caching | Yes, via `cache_read_input_tokens` on Anthropic's side | Yes, via `cached_input_tokens` (OpenAI Responses API server-side cache) |

### Tool-whitelist gap
Codex's `--sandbox read-only` permits arbitrary shell commands within the sandbox (just blocks writes). Claude's `--tools "Read,Grep,Glob"` is name-restricted. For Clearly's wiki use case this is acceptable because:
- Writes to the vault flow through `WikiOperationApplier` → diff sheet, never the agent directly.
- The agent never receives untrusted-prompt input; recipes interpolate user input as `{{input}}` content, not as system instructions.
- The sandbox itself prevents network exfiltration and out-of-cwd writes.

If a future Capture flow ingests untrusted external content (e.g., a webhook-delivered URL) we revisit. For now the looseness is fine.

### Auth model
Both runners default to subscription auth. This matches the "CLI-first to leverage flat-rate sub" framing — neither path costs the user marginal money for routine use.

### Sources
- [github.com/openai/codex](https://github.com/openai/codex) (release 0.125.0)
- [developers.openai.com/codex/cli](https://developers.openai.com/codex/cli)
- [developers.openai.com/codex/noninteractive](https://developers.openai.com/codex/noninteractive)
- [github.com/openai/codex/blob/main/codex-rs/exec/src/cli.rs](https://github.com/openai/codex/blob/main/codex-rs/exec/src/cli.rs)
- [github.com/openai/codex/blob/main/codex-rs/exec/src/exec_events.rs](https://github.com/openai/codex/blob/main/codex-rs/exec/src/exec_events.rs)

---

## 5. Native semantic search via `NLContextualEmbedding` + MCP

### Decision
Build native semantic search into Clearly. Embeddings via Apple's `NLContextualEmbedding` (built into the OS), stored as BLOBs in the existing GRDB schema, queried via brute-force cosine in Swift. Exposed as a `semantic_search` MCP tool that **both** the in-app wiki agent and external agents (Claude Desktop, etc.) consume via the existing ClearlyCLI MCP server.

### Why semantic at all (revising the initial "drop QMD" instinct)

The first research pass concluded that for personal vaults <1k notes, Grep+Read was sufficient — citing Augment's SWE-Bench analysis (agent persistence > retrieval sophistication) and Cursor's data (semantic lift only meaningful at 1k+ files). That conclusion was correct *for the median case* but missed three failure modes:

1. **Conceptual queries with no lexical anchor.** "Notes about *focus*" missing a `deep-work.md` file because nothing in it literally says "focus." Grep cannot bridge synonym gaps.
2. **Agent iteration cost.** When the first Grep is too narrow or too broad, the agent does 3-5 grep rounds. Each round is a tool round-trip. UX degrades visibly.
3. **Vault growth.** A user who starts at 50 notes can be at 500 in a year. Building no semantic infrastructure pushes the inflection point onto a future scramble.

Token math at 500 notes confirms Grep+Read still scales fine (Grep returns matches + context; agent picks ~5-15 files to Read; total context ~20KB per query, not 1MB). So semantic is *additive*, not a replacement.

### Why NOT QMD

[`tobi/qmd`](https://github.com/tobi/qmd) is a beautifully-engineered semantic-search CLI/MCP server using local GGUF models (EmbeddingGemma + Qwen3-Reranker via `node-llama-cpp`). For Clearly it's the wrong shape:

- **Distribution**: requires Node + `npm i -g @tobilu/qmd` + ~2GB of GGUF model downloads on first use. Hostile to a sandboxed Mac App Store binary; the user would need to manually install before chat works.
- **Ownership**: external dependency, external release cadence, external bug surface.
- **Failure mode**: stale embeddings return confidently-ranked but wrong snippets. Agent has no raw text to sanity-check because it didn't pick the candidates.
- **Scale fit**: optimized for Tobi's corpus (Shopify-scale meeting transcripts), not a personal vault.

The QMD-the-idea (semantic on top of structural search) is right. QMD-the-dependency is the wrong vehicle.

### Why `NLContextualEmbedding`

| Candidate | Bundle weight | Quality | Maintenance | macOS gotchas |
|---|---|---|---|---|
| `NLEmbedding.wordEmbedding` | 0 (OS-bundled) | Word-level, 300d, no context | None (OS) | Limited; word-only without mean-pooling |
| `NLEmbedding.sentenceEmbedding` | 0 | Sentence-level, 512d, ~50 langs | None (OS) | Older, behind transformer SOTA |
| **`NLContextualEmbedding`** | **0** | **Contextual transformer, 27 langs across 3 scripts** | **None (OS)** | **macOS 14+ — we're on 15+, fine** |
| CoreML MiniLM (custom) | ~22MB | Better than NL, MTEB ~0.55 | We own the conversion | Needs coremltools + tokenizer port; no battle-tested public artifact |
| Bundled GGUF | 100MB-2GB | Best | High (model + runtime) | Sandbox compatibility unclear; oversized for an editor |

`NLContextualEmbedding` is the only option that ships *today* with zero bundle weight, zero dependencies, and quality good enough for personal-vault retrieval. WWDC23 session 10042 covers it; [`NaturalLanguageEmbeddings`](https://github.com/buh/NaturalLanguageEmbeddings) is an open-source Swift package using it for exactly this purpose.

### Why brute-force cosine, not `sqlite-vec`

`sqlite-vec` requires a custom SQLite build:
- macOS system SQLite has `SQLITE_OMIT_LOAD_EXTENSION`.
- GRDB's stock build same.
- Solution: `GRDBCustomSQLite` (or `GRDBCustomSQLiteBuild`) + compile sqlite-vec's amalgamation with `SQLITE_CORE` + call `sqlite3_vec_init` at connection-open. Working reference: [SwiftedMind/GRDBCustomExample @ working-extension](https://github.com/SwiftedMind/GRDBCustomExample/tree/working-extension).

For a vault under ~50K notes, brute-force cosine over `Float32` BLOBs in Swift is sub-50ms. The build complexity buys nothing at our current scale.

### Inflection points for revisiting
- Vault > 50K notes → switch to `sqlite-vec` via custom SQLite.
- `NLContextualEmbedding` quality complaints → bundle MiniLM CoreML.
- Multilingual users hitting English-model limitations → ship per-language model selection.

### Why the in-app agent uses the same MCP tool

`claude --print` supports MCP via:
```
claude --print \
  --mcp-config <bundled-config.json> \
  --strict-mcp-config \
  --allowedTools "Read,Grep,Glob,mcp__clearly__semantic_search,mcp__clearly__search_notes" \
  ...
```

Confirmed via `claude --help` and Anthropic's MCP docs. **Stdio MCP servers (which ClearlyCLI is) work in `--print` mode.** A known bug exists for HTTP/remote MCP servers in `--print` ([anthropics/claude-code#34131](https://github.com/anthropics/claude-code/issues/34131), [#37805](https://github.com/anthropics/claude-code/issues/37805)) — irrelevant here.

`--strict-mcp-config` isolates the wiki agent from the user's global `~/.claude.json` so a misconfigured personal MCP server can't pollute wiki context. Tool whitelist syntax: `mcp__<server>__<tool>` with double underscores; wildcards work (`mcp__clearly__*`).

This means **one implementation serves both consumers**: external agents (Claude Desktop, Cursor) get `semantic_search` via the existing "Copy MCP Config" Settings flow; the in-app wiki agent gets it via a generated per-spawn config. No duplication.

### Sources
- [`NLContextualEmbedding` docs](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding)
- [`NLEmbedding.sentenceEmbedding(for:)` docs](https://developer.apple.com/documentation/naturallanguage/nlembedding/sentenceembedding(for:))
- [WWDC23 session 10042](https://developer.apple.com/videos/play/wwdc2023/10042/)
- [`buh/NaturalLanguageEmbeddings`](https://github.com/buh/NaturalLanguageEmbeddings) — Swift package using `NLContextualEmbedding` for semantic search
- [Claude Code MCP docs](https://code.claude.com/docs/en/mcp)
- [`asg017/sqlite-vec`](https://github.com/asg017/sqlite-vec)
- [GRDB custom SQLite discussion](https://github.com/groue/GRDB.swift/discussions/1761)
- [Why Grep Beat Embeddings — Augment via jxnl.co](https://jxnl.co/writing/2025/09/11/why-grep-beat-embeddings-in-our-swe-bench-agent-lessons-from-augment/)
- [Cursor: improving agent with semantic search](https://cursor.com/blog/semsearch)
- [On the Lost Nuance of Grep vs. Semantic Search](https://www.nuss-and-bolts.com/p/on-the-lost-nuance-of-grep-vs-semantic)
- [`tobi/qmd`](https://github.com/tobi/qmd)
- [Tobi Lütke's QMD — Gamgee](https://gamgee.ai/blogs/tobi-lutke-qmd-local-semantic-search/)

---

## 6. Recipe versioning is dead — drop the concept

### Decision
Remove the "future feature" framing from the `loadRecipe` comment in `Clearly/Wiki/WikiAgentCoordinator.swift`. Replace with a single line: "Recipes are bundled with the app; vault-local files are seeded as readable reference but not loaded."

### Background
Recipe versioning was a placeholder for a hypothetical migration story: if users edited `.clearly/recipes/*.md` in their vault, and we shipped updated bundled recipes (better instructions, new variables like `{{vault_state}}`), users with stale vault-local copies would silently use the old version. The proposed fix: `version: 3` frontmatter; on load, compare; migrate or warn.

### Why it's moot
Vault-local recipes are now permanently disabled. The bundled recipe always wins. Recipes are app behavior, not user content — the same way `PreviewCSS.swift` belongs to the app, not the user's `.clearly/style.css`. There is nothing to version.

### When this changes
If a user shows up needing to customize recipes (a power-user feature that conflicts with the "wiki just works" pitch), the right answer is to add a Settings → Wiki "Custom recipe directory" picker pointing at a *separate* user folder — not to re-enable vault-local recipes. Versioning still wouldn't be needed; the user owns the customization.

---

## 7. How retrieval actually works (token math)

### Question raised
"How does Claude/Codex know what to include when answering questions when there are, say, 500+ files? Does it go *read* all 500 files? Surely not. That'd cost massive tokens."

### Answer
Claude does **not** read 500 files. The retrieval loop:

1. Agent calls `Grep <term>` (one tool round-trip). Shell scans all 500 files at the OS level — cheap, not Claude tokens.
2. Grep returns matches: `path:line:matched_content` for each hit. Output size depends on hit density — typically 2-10KB for a focused term, capped by ripgrep's defaults.
3. Agent picks ~5-15 file paths from the grep output and `Read`s only those.
4. Each `Read` loads the full file into Claude's context.

### Token math at 500 files
- Single Grep output: ~5KB
- 10 Reads × ~2KB per note: ~20KB
- Total per query: **~25KB context**

vs. inlining all 500 files:
- 500 × 2KB = 1MB raw → ~250K tokens → blows past Claude's 200K context window entirely

### Where this breaks down
- **Conceptual queries** with no lexical anchor: agent grep terms miss synonyms (`"focus"` doesn't match `deep-work.md`). Semantic search closes this — covered by Item 5.
- **Iteration thrash**: if first Grep is wrong, agent iterates 3-5 times. Each round is a round-trip; UX degrades.
- **>5K files**: `ripgrep` itself becomes slow and noisy.

This is why Item 5 ships native semantic — additive to Grep+Read, not replacing it. The agent picks per query: Grep for proper nouns / file paths / exact phrases, semantic for conceptual / synonym queries.

### Sources
- [Why Grep Beat Embeddings — Augment via jxnl.co](https://jxnl.co/writing/2025/09/11/why-grep-beat-embeddings-in-our-swe-bench-agent-lessons-from-augment/)
- [Simon Willison on FTS in agent loops (HN)](https://news.ycombinator.com/item?id=46080933)
- [Cursor: improving agent with semantic search](https://cursor.com/blog/semsearch)

---

## Cross-cutting decisions summary

| Topic | Decision | Why |
|---|---|---|
| API key path | Drop entirely | No real users on it; CLI subscription is the path |
| Welcome state | Seed `getting-started.md` | Editable, deletable, no new UI |
| Review trigger | Auto on vault open >24h | Daily cadence; manual was invisible |
| Review surface | Sidebar badge | Don't interrupt user's flow |
| Codex CLI | Add as switchable runner | Adapter pattern already in place; sub auth matches Claude model |
| Tool whitelist | Accept Codex's `--sandbox read-only` looseness | Writes mediated by `WikiOperationApplier` regardless |
| Semantic search | Build native via `NLContextualEmbedding` | Zero bundle weight, on-device, OS-shipped |
| Vector storage | Brute-force cosine over BLOBs | Sub-50ms at <50K notes; defer `sqlite-vec` |
| MCP integration | In-app agent uses same MCP server as external | One implementation, two consumers |
| Vault-local recipes | Stay disabled | Recipes are app behavior; versioning unnecessary |
| QMD as a dependency | No | Wrong shape for sandboxed Mac App Store; superseded by native semantic |

---

## Open questions (deferred to implementation)

1. **Codex MCP support**: Does `codex exec` accept `--mcp-config`? If not, semantic search ships Claude-only and Codex falls back to Grep+Read. Verify in implementation; either outcome is acceptable.
2. **Embedding refresh strategy**: Should re-embedding on file change be debounced (wait for typing to settle), or fire on every save? Lean toward debounce (~5s) to avoid CPU thrash during rapid edits.
3. **Cosine threshold for "no result"**: What similarity score counts as a meaningful hit vs noise? Likely empirical — start at 0.5, tune from real-vault testing.
4. **Embedding model version bumps**: When Apple updates `NLContextualEmbedding` in a future macOS release, do we need to re-embed everything? The `model_version INTEGER` column in the schema lets us bump and trigger a one-time reindex; mechanism is in place.
5. **First-run reindex UX**: Embedding 500 notes takes ~30s on Apple Silicon. Should there be a progress indicator, or is it silent background work? Lean toward silent (the existing FSEvents indexing is silent too).

---

## Source index (consolidated)

### Anthropic / Claude Code
- [code.claude.com/docs/en/mcp](https://code.claude.com/docs/en/mcp)
- [code.claude.com/docs/en/agent-sdk/mcp](https://code.claude.com/docs/en/agent-sdk/mcp)
- [anthropics/claude-code#34131](https://github.com/anthropics/claude-code/issues/34131)
- [anthropics/claude-code#37805](https://github.com/anthropics/claude-code/issues/37805)

### OpenAI / Codex
- [github.com/openai/codex](https://github.com/openai/codex)
- [developers.openai.com/codex/cli](https://developers.openai.com/codex/cli)
- [developers.openai.com/codex/noninteractive](https://developers.openai.com/codex/noninteractive)
- [codex-rs/exec/src/cli.rs](https://github.com/openai/codex/blob/main/codex-rs/exec/src/cli.rs)
- [codex-rs/exec/src/exec_events.rs](https://github.com/openai/codex/blob/main/codex-rs/exec/src/exec_events.rs)

### Apple Natural Language
- [developer.apple.com/.../nlcontextualembedding](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding)
- [developer.apple.com/.../nlembedding/sentenceembedding](https://developer.apple.com/documentation/naturallanguage/nlembedding/sentenceembedding(for:))
- [WWDC23 session 10042](https://developer.apple.com/videos/play/wwdc2023/10042/)
- [github.com/buh/NaturalLanguageEmbeddings](https://github.com/buh/NaturalLanguageEmbeddings)

### Vector storage
- [github.com/asg017/sqlite-vec](https://github.com/asg017/sqlite-vec)
- [GRDB custom SQLite discussion #1761](https://github.com/groue/GRDB.swift/discussions/1761)
- [SwiftedMind/GRDBCustomExample @ working-extension](https://github.com/SwiftedMind/GRDBCustomExample/tree/working-extension)

### Retrieval philosophy
- [Why Grep Beat Embeddings — Augment](https://jxnl.co/writing/2025/09/11/why-grep-beat-embeddings-in-our-swe-bench-agent-lessons-from-augment/)
- [Cursor: improving agent with semantic search](https://cursor.com/blog/semsearch)
- [On the Lost Nuance of Grep vs. Semantic Search](https://www.nuss-and-bolts.com/p/on-the-lost-nuance-of-grep-vs-semantic)
- [Simon Willison on FTS in agent loops (HN)](https://news.ycombinator.com/item?id=46080933)

### QMD (rejected dependency)
- [github.com/tobi/qmd](https://github.com/tobi/qmd)
- [Tobi Lütke's QMD — Gamgee](https://gamgee.ai/blogs/tobi-lutke-qmd-local-semantic-search/)
- [Introducing lazyqmd](https://alexanderzeitler.com/articles/introducing-lazyqmd-a-tui-for-qmd/)
