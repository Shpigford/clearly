#!/usr/bin/env bash
#
# Populate debugfixture/ for Debug iOS builds. The app copies this folder into
# the bundle as DebugFixtureVault and mounts it as a writable vault at launch.
#
# Usage:
#   ./scripts/setup-debugfixture.sh walden  # one large-ish public-domain book
#   ./scripts/setup-debugfixture.sh all     # full markdown collection stress test
#   ./scripts/setup-debugfixture.sh clean   # remove generated fixture contents

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST="${DEBUGFIXTURE_DIR:-$REPO_ROOT/debugfixture}"

SOURCE_REPO="mlschmitt/classic-books-markdown"
SOURCE_BRANCH="main"
RAW_BASE="https://raw.githubusercontent.com/$SOURCE_REPO/$SOURCE_BRANCH"
ZIP_URL="https://github.com/$SOURCE_REPO/archive/refs/heads/$SOURCE_BRANCH.zip"
WALDEN_PATH="Henry David Thoreau/Walden.md"

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
}

reset_fixture() {
  rm -rf "$DEST"
  mkdir -p "$DEST"
}

download_walden() {
  reset_fixture
  mkdir -p "$DEST/$(dirname "$WALDEN_PATH")"
  curl -fsSL "$RAW_BASE/${WALDEN_PATH// /%20}" -o "$DEST/$WALDEN_PATH"
}

download_all() {
  reset_fixture
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  local zip="$tmp/classic-books-markdown.zip"
  curl -fsSL "$ZIP_URL" -o "$zip"
  ditto -x -k "$zip" "$tmp"

  local source_root="$tmp/classic-books-markdown-$SOURCE_BRANCH"
  if [ ! -d "$source_root" ]; then
    echo "Expected archive root not found: $source_root" >&2
    exit 1
  fi

  while IFS= read -r -d '' file; do
    local rel="${file#$source_root/}"
    mkdir -p "$DEST/$(dirname "$rel")"
    cp "$file" "$DEST/$rel"
  done < <(find "$source_root" -type f -name '*.md' -print0)
}

print_summary() {
  local count
  count="$(find "$DEST" -type f -name '*.md' | wc -l | tr -d ' ')"
  echo "Prepared $count markdown file(s) in $DEST"
}

case "${1:-}" in
  walden)
    download_walden
    print_summary
    ;;
  all)
    download_all
    print_summary
    ;;
  clean)
    rm -rf "$DEST"
    echo "Removed $DEST"
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unknown mode: $1" >&2
    echo >&2
    usage >&2
    exit 64
    ;;
esac
