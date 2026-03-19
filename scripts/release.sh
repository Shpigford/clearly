#!/bin/bash
set -euo pipefail

# Usage: ./scripts/release.sh 1.0.0
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

VERSION="${1:?Usage: ./scripts/release.sh <version>}"
TEAM_ID="${APPLE_TEAM_ID:?Set APPLE_TEAM_ID in .env}"
SIGNING_IDENTITY="Developer ID Application: ${SIGNING_IDENTITY_NAME:?Set SIGNING_IDENTITY_NAME in .env} ($TEAM_ID)"
APPLE_ID="${APPLE_ID:?Set APPLE_ID in .env}"
BUNDLE_ID="com.sabotage.clearly"

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
  archive \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION"

# Export
sed "s/\${APPLE_TEAM_ID}/$TEAM_ID/g" ExportOptions.plist > build/ExportOptions.plist
xcodebuild -exportArchive \
  -archivePath build/Clearly.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist \
  -exportPath build/export

echo "📦 Creating DMG..."
hdiutil create -volname "Clearly" \
  -srcfolder build/export/Clearly.app \
  -ov -format UDZO \
  build/Clearly.dmg

echo "🔏 Notarizing..."
xcrun notarytool submit build/Clearly.dmg \
  --keychain-profile "AC_PASSWORD" \
  --wait

echo "📎 Stapling..."
xcrun stapler staple build/export/Clearly.app
rm build/Clearly.dmg
hdiutil create -volname "Clearly" \
  -srcfolder build/export/Clearly.app \
  -ov -format UDZO \
  build/Clearly.dmg
xcrun stapler staple build/Clearly.dmg || echo "⚠️  DMG staple failed (normal — CDN propagation delay). App inside is stapled."

echo "🏷️  Tagging v$VERSION..."
git tag "v$VERSION"
git push --tags

echo "📡 Generating Sparkle appcast..."
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData/Clearly-*/SourcePackages/artifacts/sparkle/Sparkle/bin -maxdepth 0 2>/dev/null | head -1)
SIGNATURE=$("$SPARKLE_BIN/sign_update" build/Clearly.dmg 2>&1)
ED_SIG=$(echo "$SIGNATURE" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
LENGTH=$(echo "$SIGNATURE" | grep -o 'length="[^"]*"' | cut -d'"' -f2)
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

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
      <enclosure
        url="https://github.com/Shpigford/clearly/releases/download/v$VERSION/Clearly.dmg"
        sparkle:edSignature="$ED_SIG"
        length="$LENGTH"
        type="application/octet-stream"
      />
    </item>
  </channel>
</rss>
APPCAST

echo "📡 Updating site appcast..."
cp build/appcast.xml website/appcast.xml
git add website/appcast.xml
git commit -m "chore: update appcast for v$VERSION" || true
git push

echo "🚀 Creating GitHub Release..."
gh release create "v$VERSION" build/Clearly.dmg \
  --title "Clearly v$VERSION" \
  --generate-notes

echo "✅ Done! Release: https://github.com/Shpigford/clearly/releases/tag/v$VERSION"
