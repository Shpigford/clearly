#!/usr/bin/env bash
set -euo pipefail
APP="${1:?usage: verify-entitlements.sh <path-to-.app>}"
OUT=$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)

for key in \
  "com.apple.developer.icloud-container-identifiers" \
  "com.apple.developer.icloud-services"
do
  if ! grep -q "$key" <<<"$OUT"; then
    echo "❌ Missing entitlement on $APP: $key"
    echo "   (Xcode likely stripped it during archive/export — re-sign with the full plist.)"
    exit 1
  fi
done
if ! grep -q "iCloud.com.sabotage.clearly" <<<"$OUT"; then
  echo "❌ iCloud container id missing from entitlements on $APP."
  exit 1
fi
echo "✅ iCloud entitlements present on $APP"
