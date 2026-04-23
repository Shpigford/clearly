#!/bin/bash
set -euo pipefail

# Usage: ./scripts/release.sh [--dry-run] 1.0.0
#
# Options:
#   --dry-run  Build, sign, and verify only. Skips notarization, GitHub, and appcast.
#
# Reads credentials from .env in the project root.
# See .env.example for required variables:
#   APPLE_TEAM_ID          — Apple Developer Team ID
#   APPLE_ID               — Apple ID email for notarization
#   SIGNING_IDENTITY_NAME  — e.g. "Sabotage Media, LLC"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/../.env" ]; then
  set -a
  source "$SCRIPT_DIR/../.env"
  set +a
fi

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
  shift
fi

VERSION="${1:?Usage: ./scripts/release.sh [--dry-run] <version>}"

# Extract changelog entries for a version and convert to HTML <ul>
extract_changelog() {
  local version="$1"
  local changelog="$2"
  local in_section=false
  local html="<ul>"

  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ \[${version}\] ]]; then
      in_section=true
      continue
    fi
    if $in_section && [[ "$line" =~ ^##\  ]]; then
      break
    fi
    if $in_section && [[ "$line" =~ ^-\ (.+) ]]; then
      html+="<li>${BASH_REMATCH[1]}</li>"
    fi
  done < "$changelog"

  html+="</ul>"
  if [ "$html" = "<ul></ul>" ]; then
    echo ""
  else
    echo "$html"
  fi
}

# Extract raw markdown changelog entries for a version
extract_changelog_markdown() {
  local version="$1"
  local changelog="$2"
  local in_section=false
  local md=""

  while IFS= read -r line; do
    if [[ "$line" =~ ^##\ \[${version}\] ]]; then
      in_section=true
      continue
    fi
    if $in_section && [[ "$line" =~ ^##\  ]]; then
      break
    fi
    if $in_section && [[ "$line" =~ ^-\ (.+) ]]; then
      md+="- ${BASH_REMATCH[1]}"$'\n'
    fi
  done < "$changelog"

  echo "$md"
}
# Create a styled DMG with app icon and Applications drop link
create_clearly_dmg() {
  local output_path="$1"
  rm -f "$output_path"

  create-dmg \
    --volname "Clearly" \
    --background "$SCRIPT_DIR/dmg-background@2x.png" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 160 \
    --text-size 14 \
    --icon "Clearly.app" 170 180 \
    --hide-extension "Clearly.app" \
    --app-drop-link 490 180 \
    --no-internet-enable \
    --format UDZO \
    "$output_path" \
    build/export/Clearly.app || true

  [ -f "$output_path" ] || { echo "❌ DMG creation failed"; exit 1; }
}

TEAM_ID="${APPLE_TEAM_ID:?Set APPLE_TEAM_ID in .env}"
SIGNING_IDENTITY="Developer ID Application: ${SIGNING_IDENTITY_NAME:?Set SIGNING_IDENTITY_NAME in .env} ($TEAM_ID)"
APPLE_ID="${APPLE_ID:?Set APPLE_ID in .env}"
BUNDLE_ID="com.sabotage.clearly"

if ! $DRY_RUN; then
  if ! command -v create-dmg &>/dev/null; then
    echo "❌ create-dmg not found. Install with: brew install create-dmg"
    exit 1
  fi

  if ! xcrun notarytool history --keychain-profile "AC_PASSWORD" >/dev/null 2>&1; then
    echo "❌ Unable to use notarytool keychain profile \"AC_PASSWORD\"."
    echo "Create or refresh it with:"
    echo "  xcrun notarytool store-credentials \"AC_PASSWORD\" --apple-id \"$APPLE_ID\" --team-id \"$TEAM_ID\" --password \"<app-specific-password>\""
    exit 1
  fi
fi

echo "🔨 Building Clearly v$VERSION..."

# Generate Xcode project
xcodegen generate

# Clean build
rm -rf build
mkdir -p build

# Archive
xcodebuild -project Clearly.xcodeproj \
  -scheme Clearly \
  -configuration Release \
  -archivePath build/Clearly.xcarchive \
  -allowProvisioningUpdates \
  archive \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION"

# Export
sed "s/\${APPLE_TEAM_ID}/$TEAM_ID/g" ExportOptions.plist > build/ExportOptions.plist
xcodebuild -exportArchive \
  -archivePath build/Clearly.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates

echo "🔑 Re-signing with sandbox entitlements (inside-out)..."
sed "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/g" Clearly/Clearly.entitlements > build/Clearly.entitlements
cp ClearlyQuickLook/ClearlyQuickLook.entitlements build/ClearlyQuickLook.entitlements

SPARKLE_FRAMEWORK="build/export/Clearly.app/Contents/Frameworks/Sparkle.framework"
if [ ! -d "$SPARKLE_FRAMEWORK" ]; then
  echo "❌ Sparkle.framework not found at expected path. Check export output."
  exit 1
fi

# 1. Sparkle XPC services (innermost)
for xpc in "$SPARKLE_FRAMEWORK"/Versions/B/XPCServices/*.xpc; do
  echo "  Signing $(basename "$xpc")..."
  codesign -f -s "$SIGNING_IDENTITY" -o runtime --timestamp "$xpc"
done

# 2. Sparkle.framework
echo "  Signing Sparkle.framework..."
codesign -f -s "$SIGNING_IDENTITY" -o runtime --timestamp "$SPARKLE_FRAMEWORK"

# 3. QuickLook extension (with its own entitlements)
echo "  Signing ClearlyQuickLook.appex..."
codesign -f -s "$SIGNING_IDENTITY" -o runtime --timestamp \
  --entitlements build/ClearlyQuickLook.entitlements \
  "build/export/Clearly.app/Contents/PlugIns/ClearlyQuickLook.appex"

# 4. Main app (outermost)
echo "  Signing Clearly.app..."
codesign -f -s "$SIGNING_IDENTITY" -o runtime --timestamp \
  --entitlements build/Clearly.entitlements \
  build/export/Clearly.app

# Verify mach-lookup entitlements survived
if ! codesign -d --entitlements :- build/export/Clearly.app 2>/dev/null | grep -q "mach-lookup"; then
  echo "❌ mach-lookup entitlements missing after re-sign. Aborting."
  exit 1
fi

# Verify iCloud entitlements survived
scripts/verify-entitlements.sh build/export/Clearly.app

# Deep signature chain verification
codesign --verify --deep --strict build/export/Clearly.app
echo "✅ Code signature verified (deep + strict)."

if $DRY_RUN; then
  echo "🏁 Dry run complete. Signed app at: build/export/Clearly.app"
  echo "   To inspect: codesign -d --entitlements :- build/export/Clearly.app"
  echo "   Note: spctl --assess will fail until notarized (expected in dry-run)."
  exit 0
fi

echo "📦 Creating DMG..."
create_clearly_dmg build/Clearly.dmg

echo "🔏 Notarizing..."
xcrun notarytool submit build/Clearly.dmg \
  --keychain-profile "AC_PASSWORD" \
  --wait

echo "📎 Stapling..."
xcrun stapler staple build/export/Clearly.app
rm build/Clearly.dmg
create_clearly_dmg build/Clearly.dmg
xcrun stapler staple build/Clearly.dmg || echo "⚠️  DMG staple failed (normal — CDN propagation delay). App inside is stapled."

# Gatekeeper assessment (must run after notarization + stapling)
spctl --assess --type execute --verbose build/export/Clearly.app
echo "✅ Gatekeeper assessment passed."

echo "🏷️  Tagging v$VERSION..."
git tag "v$VERSION"
git push --tags

echo "📡 Generating Sparkle appcast..."
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData/Clearly-*/SourcePackages/artifacts/sparkle/Sparkle/bin -maxdepth 0 2>/dev/null | head -1)
SIGNATURE=$("$SPARKLE_BIN/sign_update" build/Clearly.dmg 2>&1)
ED_SIG=$(echo "$SIGNATURE" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(echo "$SIGNATURE" | grep -o 'length="[^"]*"' | cut -d'"' -f2)
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

# Extract release notes from CHANGELOG.md
RELEASE_NOTES=$(extract_changelog "$VERSION" "CHANGELOG.md")
if [ -z "$RELEASE_NOTES" ]; then
  echo "⚠️  No changelog entry for v$VERSION in CHANGELOG.md. Appcast will have no release notes."
fi

# Preserve existing items from current appcast (exclude current version if re-releasing)
EXISTING_ITEMS=""
if [ -f website/appcast.xml ]; then
  EXISTING_ITEMS=$(awk '
    /<item>/ { buf=""; capture=1 }
    capture { buf = buf $0 "\n" }
    /<\/item>/ {
      capture=0
      if (buf !~ /<sparkle:version>'"$VERSION"'</) printf "%s", buf
    }
  ' website/appcast.xml)
fi

# Build description element if we have release notes
DESC_ELEMENT=""
if [ -n "$RELEASE_NOTES" ]; then
  DESC_ELEMENT="      <description><![CDATA[$RELEASE_NOTES]]></description>"
fi

cat > build/appcast.xml << APPCAST
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
  <channel>
    <title>Clearly</title>
    <item>
      <title>Version $VERSION</title>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <pubDate>$PUB_DATE</pubDate>
$DESC_ELEMENT
      <enclosure
        url="https://github.com/Shpigford/clearly/releases/download/v$VERSION/Clearly.dmg"
        sparkle:edSignature="$ED_SIG"
        length="$LENGTH"
        type="application/octet-stream"
      />
    </item>
$EXISTING_ITEMS
  </channel>
</rss>
APPCAST

echo "📡 Updating site appcast..."
cp build/appcast.xml website/appcast.xml
source "$SCRIPT_DIR/lib/changelog-html.sh"
generate_changelog_html
git add website/appcast.xml website/changelog.html
git commit -m "chore: update appcast for v$VERSION" || true
git push

echo "🚀 Creating GitHub Release..."
CHANGELOG_MD=$(extract_changelog_markdown "$VERSION" "CHANGELOG.md")
if [ -n "$CHANGELOG_MD" ]; then
  gh release create "v$VERSION" build/Clearly.dmg \
    --title "Clearly v$VERSION" \
    --notes "$CHANGELOG_MD"
else
  gh release create "v$VERSION" build/Clearly.dmg \
    --title "Clearly v$VERSION" \
    --generate-notes
fi

echo "✅ Done! Release: https://github.com/Shpigford/clearly/releases/tag/v$VERSION"
