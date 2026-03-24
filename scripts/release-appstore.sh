#!/bin/bash
set -euo pipefail

# Usage: ./scripts/release-appstore.sh 1.7.0
#
# Builds Clearly without Sparkle and uploads to App Store Connect.
# Reads credentials from .env in the project root (same as release.sh).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

VERSION="${1:?Usage: ./scripts/release-appstore.sh <version>}"
TEAM_ID="${APPLE_TEAM_ID:?Set APPLE_TEAM_ID in .env}"
BUILD_NUMBER=$(date +%Y%m%d%H%M)

echo "🍎 Building Clearly v$VERSION (build $BUILD_NUMBER) for App Store..."

# Clean build
rm -rf build
mkdir -p build

# ── 1. Strip Sparkle keys from Info.plist (in place, restored later) ─────────
cp Clearly/Info.plist build/Info-Original.plist
/usr/libexec/PlistBuddy \
  -c "Delete :SUFeedURL" \
  -c "Delete :SUPublicEDKey" \
  -c "Delete :SUEnableInstallerLauncherService" \
  Clearly/Info.plist

# ── 2. Generate project.yml without Sparkle ─────────────────────────────────
sed \
  -e '/^  Sparkle:$/,/from:/d' \
  -e '/- package: Sparkle/d' \
  -e 's|Clearly/Clearly.entitlements|Clearly/Clearly-AppStore.entitlements|' \
  project.yml > build/project-appstore.yml

# ── 3. Generate Xcode project from modified spec ────────────────────────────
xcodegen generate --spec build/project-appstore.yml -p . -r .

# ── 4. Archive ──────────────────────────────────────────────────────────────
echo "📦 Archiving..."
xcodebuild -project Clearly.xcodeproj \
  -scheme Clearly \
  -configuration Release \
  -archivePath build/Clearly-AppStore.xcarchive \
  archive \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

# Verify no Sparkle in archive
if find build/Clearly-AppStore.xcarchive -name "Sparkle*" | grep -q .; then
  echo "❌ Sparkle framework found in archive. Aborting."
  exit 1
fi
echo "✅ Archive clean — no Sparkle framework."

# ── 5. Export + upload to App Store Connect ──────────────────────────────────
echo "🚀 Uploading to App Store Connect..."
sed "s/\${APPLE_TEAM_ID}/$TEAM_ID/g" ExportOptions-AppStore.plist > build/ExportOptions-AppStore.plist
xcodebuild -exportArchive \
  -archivePath build/Clearly-AppStore.xcarchive \
  -exportOptionsPlist build/ExportOptions-AppStore.plist \
  -exportPath build/export-appstore \
  -allowProvisioningUpdates

# ── 6. Restore Info.plist and Xcode project (with Sparkle) ──────────────────
echo "🔄 Restoring Sparkle project..."
mv build/Info-Original.plist Clearly/Info.plist
xcodegen generate

echo "✅ Uploaded Clearly v$VERSION (build $BUILD_NUMBER) to App Store Connect."
echo "   Check status at: https://appstoreconnect.apple.com"
