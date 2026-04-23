#!/bin/bash
set -euo pipefail

# Usage: ./scripts/release-ios.sh 2.4.0
#
# Archives the iOS app for App Store / TestFlight distribution and uploads
# to App Store Connect. No Apple Review submission — the build lands on
# TestFlight's internal testing track, where you finish the encryption
# export-compliance questionnaire and invite testers from the ASC UI.
#
# Prerequisites (one-time):
#   • iOS app record exists in App Store Connect for bundle id com.sabotage.clearly.
#   • .env in the repo root contains APPLE_TEAM_ID (same .env used by
#     release.sh and release-appstore.sh).
#   • Xcode is signed into the same Apple ID as your ASC account so
#     -allowProvisioningUpdates can fetch the Apple Distribution profile.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

VERSION="${1:?Usage: ./scripts/release-ios.sh <version>}"
TEAM_ID="${APPLE_TEAM_ID:?Set APPLE_TEAM_ID in .env}"
BUILD_NUMBER=$(date +%Y%m%d%H%M)

echo "📱 Building Clearly iOS v$VERSION (build $BUILD_NUMBER) for TestFlight..."

# Clean build
rm -rf build/Clearly-iOS.xcarchive build/export-ios
mkdir -p build

# ── 1. Generate project ──────────────────────────────────────────────────────
xcodegen generate

# ── 2. Archive ───────────────────────────────────────────────────────────────
echo "📦 Archiving Clearly-iOS..."
xcodebuild -project Clearly.xcodeproj \
  -scheme Clearly-iOS \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Clearly-iOS.xcarchive \
  archive \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

# ── 3. Export + upload to App Store Connect (→ TestFlight) ───────────────────
echo "🚀 Exporting and uploading to App Store Connect..."
sed "s/\${APPLE_TEAM_ID}/$TEAM_ID/g" ExportOptions-iOS.plist > build/ExportOptions-iOS.plist
xcodebuild -exportArchive \
  -archivePath build/Clearly-iOS.xcarchive \
  -exportOptionsPlist build/ExportOptions-iOS.plist \
  -exportPath build/export-ios \
  -allowProvisioningUpdates

echo ""
echo "✅ Clearly iOS v$VERSION (build $BUILD_NUMBER) uploaded."

# ── 4. Tag and push ──────────────────────────────────────────────────────────
TAG="ios-v$VERSION"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "⚠️  Tag $TAG already exists — skipping tag step."
else
  echo "🏷️  Tagging $TAG and pushing..."
  git tag -a "$TAG" -m "iOS release $VERSION (build $BUILD_NUMBER)"
  git push origin "$TAG"
fi

# ── 5. Regenerate public changelog page ──────────────────────────────────────
echo "📡 Regenerating changelog page..."
source "$SCRIPT_DIR/lib/changelog-html.sh"
generate_changelog_html
if ! git diff --quiet website/changelog.html; then
  git add website/changelog.html
  git commit -m "chore: update changelog for ios-v$VERSION"
  git push
fi

echo ""
echo "Next steps (manual, in App Store Connect):"
echo "  1. Open https://appstoreconnect.apple.com → your iOS app → TestFlight"
echo "  2. Wait for the build to finish processing (usually 5–15 minutes)"
echo "  3. Answer the encryption export-compliance question"
echo "  4. Add internal testers, or create an external testing group + invite"
