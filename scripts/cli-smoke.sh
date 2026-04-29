#!/usr/bin/env bash
#
# CLI smoke test for the `clearly` binary. Runs every subcommand against the
# ClearlyCLIIntegrationTests fixture vault, validating JSON shape via jq and
# asserting exit codes on the error paths. Also drives the stdio MCP surface
# with a hand-rolled JSON-RPC frame.
#
# Exit 0 on full pass, nonzero on any assertion failure.
#
# Used locally and from .github/workflows/test.yml.

set -euo pipefail
IFS=$'\n\t'

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"
# Resolve to canonical case — `list_notes` compares the vault path prefix
# case-sensitively, so on case-insensitive APFS we need the real casing.
# `realpath` on macOS (from coreutils or the builtin) canonicalizes case;
# `pwd -P` does not.
FIXTURE="$(realpath "$REPO_ROOT/ClearlyCLIIntegrationTests/FixtureVault")"
BUNDLE_ID="com.sabotage.clearly.smoke.$$"

if [ ! -d "$FIXTURE" ]; then
    echo "FixtureVault not found at $FIXTURE" >&2
    exit 10
fi

# ─── Build ─────────────────────────────────────────────────────────────────
# Pin DerivedData to a workspace-local path so parallel Conductor worktrees
# don't cross-contaminate. CLAUDE.md mandates this for any direct xcodebuild
# invocation.
DERIVED="$REPO_ROOT/.build/DerivedData"
echo "→ xcodebuild -scheme ClearlyCLI -configuration Debug build"
xcodebuild -scheme ClearlyCLI -configuration Debug build -quiet -derivedDataPath "$DERIVED" >/dev/null

CLI="$DERIVED/Build/Products/Debug/ClearlyCLI"
if [ ! -x "$CLI" ]; then
    echo "ClearlyCLI binary not found at $CLI" >&2
    exit 11
fi
echo "  using $CLI"

clearly() {
    local sub="$1"; shift
    # Nested subcommands (`vaults list`, `index rebuild`) need --vault /
    # --bundle-id after the leaf verb, not the parent.
    case "$sub" in
        vaults|index)
            local verb="$1"; shift
            "$CLI" "$sub" "$verb" --vault "$FIXTURE" --bundle-id "$BUNDLE_ID" "$@"
            ;;
        *)
            "$CLI" "$sub" --vault "$FIXTURE" --bundle-id "$BUNDLE_ID" "$@"
            ;;
    esac
}
trap 'rm -rf "$HOME/Library/Application Support/$BUNDLE_ID" "$FIXTURE/Smoke"' EXIT

# ─── Happy path: every subcommand emits valid JSON ─────────────────────────
# Seed the index first. `index rebuild` is idempotent.
echo "→ index rebuild"
clearly index rebuild | jq -e '.rebuilt == true' >/dev/null

echo "→ vaults list"
clearly vaults list | jq -e '.name and .path and .file_count' >/dev/null

echo "→ search"
HITS=$(clearly search "Link" --limit 5 | jq -c . | wc -l | tr -d ' ')
if [ "$HITS" -lt 1 ]; then echo "search: expected ≥1 hit" >&2; exit 20; fi

echo "→ list"
clearly list | jq -e '.relative_path and .vault and .size_bytes' >/dev/null
NOTES=$(clearly list | wc -l | tr -d ' ')
if [ "$NOTES" -lt 7 ]; then echo "list: expected ≥7 notes, got $NOTES" >&2; exit 21; fi

echo "→ list --under Notes/"
UNDER=$(clearly list --under "Notes/" | wc -l | tr -d ' ')
if [ "$UNDER" -ne 3 ]; then echo "list --under: expected 3, got $UNDER" >&2; exit 22; fi

echo "→ read"
clearly read "Daily/2026-04-17.md" | jq -e '.content_hash | length == 64' >/dev/null
clearly read "Daily/2026-04-17.md" --start-line 1 --end-line 2 \
  | jq -e '.line_range.start == 1 and .line_range.end == 2' >/dev/null

echo "→ headings"
clearly headings "Daily/2026-04-17.md" \
  | jq -e '.headings | map(.text) | index("2026-04-17")' >/dev/null

echo "→ frontmatter"
clearly frontmatter "Projects/Plan.md" \
  | jq -e '.has_frontmatter and .frontmatter.title == "Project Plan"' >/dev/null
clearly frontmatter "Notes/Link Target.md" \
  | jq -e '.has_frontmatter == false' >/dev/null

echo "→ backlinks"
clearly backlinks "Notes/Link Target.md" \
  | jq -e '.linked | length >= 3' >/dev/null

echo "→ tags"
clearly tags | jq -e '.count and .tag' >/dev/null
clearly tags architecture \
  | jq -e '.relative_path and .vault' >/dev/null

echo "→ create + update + read round trip"
NEW_REL="Smoke/smoke-$$-$(date +%s).md"
clearly create "$NEW_REL" --content "# smoke\n\nbody\n" \
  | jq -e '.relative_path' >/dev/null
clearly update "$NEW_REL" --mode append --content $'\nadded\n' \
  | jq -e '.relative_path' >/dev/null
clearly read "$NEW_REL" | jq -e '.content | contains("added")' >/dev/null
rm -f "$FIXTURE/$NEW_REL"
rmdir "$FIXTURE/Smoke" 2>/dev/null || true

# ─── Error paths: exit codes ───────────────────────────────────────────────
set +e
echo "→ error: read missing → exit 3"
clearly read "does/not/exist.md" >/dev/null 2>&1; rc=$?
if [ $rc -ne 3 ]; then echo "expected 3, got $rc" >&2; exit 30; fi

echo "→ error: read traversal → exit 4"
clearly read "../etc/passwd" >/dev/null 2>&1; rc=$?
if [ $rc -ne 4 ]; then echo "expected 4, got $rc" >&2; exit 31; fi

echo "→ error: update invalid --mode → exit 64 (EX_USAGE from ArgumentParser)"
clearly update "Daily/2026-04-17.md" --mode nope --content x >/dev/null 2>&1; rc=$?
# ArgumentParser catches the bad enum value at parse time and exits 64,
# before our ToolError.invalidArgument (exit 2) fires. The MCP path, which
# validates inside Handlers.structuredCall, returns invalid_argument.
if [ $rc -ne 64 ]; then echo "expected 64, got $rc" >&2; exit 32; fi

echo "→ error: index --in-vault unknown → exit 3"
clearly index rebuild --in-vault no-such-vault >/dev/null 2>&1; rc=$?
if [ $rc -ne 3 ]; then echo "expected 3, got $rc" >&2; exit 33; fi
set -e

# ─── MCP stdio: initialize + tools/list + tools/call ───────────────────────
echo "→ mcp: initialize + tools/list"
# Hold stdin open briefly after the final request so the server has time to
# write responses before `waitUntilCompleted` returns on transport EOF.
RESPONSES=$({ printf '%s\n%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"smoke","version":"0.0.1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'; sleep 1; } \
    | "$CLI" mcp --vault "$FIXTURE" --bundle-id "$BUNDLE_ID" 2>/dev/null)

# tools/list comes back as id: 2
TOOL_COUNT=$(printf '%s\n' "$RESPONSES" | jq -s '.[] | select(.id == 2) | .result.tools | length' | head -1)
if [ "$TOOL_COUNT" != "12" ]; then
    echo "mcp tools/list: expected 12 tools, got $TOOL_COUNT" >&2
    exit 40
fi

# Spot-check that the new tools show up alongside the originals.
TOOL_NAMES=$(printf '%s\n' "$RESPONSES" | jq -rs '.[] | select(.id == 2) | .result.tools[].name' | sort | tr '\n' ' ')
for required in semantic_search find_related search_notes get_backlinks get_tags read_note list_notes get_headings get_frontmatter create_note update_note move_note; do
    if ! printf '%s' "$TOOL_NAMES" | grep -q -w "$required"; then
        echo "mcp tools/list: missing tool '$required' in: $TOOL_NAMES" >&2
        exit 40
    fi
done

echo "→ mcp: tools/call read_note (success + error)"
CALL_RESPONSES=$({ printf '%s\n%s\n%s\n%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"smoke","version":"0.0.1"}}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"read_note","arguments":{"relative_path":"Daily/2026-04-17.md"}}}' \
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"read_note","arguments":{"relative_path":"does/not/exist.md"}}}'; sleep 1; } \
    | "$CLI" mcp --vault "$FIXTURE" --bundle-id "$BUNDLE_ID" 2>/dev/null)

SUCCESS_ERROR=$(printf '%s\n' "$CALL_RESPONSES" | jq -s '.[] | select(.id == 2) | .result.isError // false' | head -1)
if [ "$SUCCESS_ERROR" != "false" ]; then
    echo "mcp success call: isError should be false/absent, got $SUCCESS_ERROR" >&2
    exit 41
fi

ERR_IDENT=$(printf '%s\n' "$CALL_RESPONSES" | jq -s '.[] | select(.id == 3) | .result.structuredContent.error' | head -1)
if [ "$ERR_IDENT" != "\"note_not_found\"" ]; then
    echo "mcp error call: expected error=note_not_found, got $ERR_IDENT" >&2
    exit 42
fi

echo ""
echo "✓ smoke test passed"
