#!/usr/bin/env bash
set -euo pipefail
APP="${1:?usage: verify-entitlements.sh <path-to-.app>}"
OUT=$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)

for key in \
  "com.apple.security.files.user-selected.read-write" \
  "com.apple.security.network.client" \
  "com.apple.security.print"
do
  if ! grep -q "$key" <<<"$OUT"; then
    echo "❌ Missing entitlement on $APP: $key"
    exit 1
  fi
done
echo "✅ Required entitlements present on $APP"
