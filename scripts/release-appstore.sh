#!/bin/bash
set -euo pipefail

# Usage: ./scripts/release-appstore.sh 1.7.0
#
# Builds Clearly without Sparkle, uploads to App Store Connect,
# creates a version, sets "What's New" from CHANGELOG.md, and submits for review.
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
ASC_KEY_ID="${ASC_KEY_ID:?Set ASC_KEY_ID in .env}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:?Set ASC_ISSUER_ID in .env}"
ASC_KEY_FILE="${ASC_KEY_FILE:?Set ASC_KEY_FILE in .env}"
ASC_KEY_FILE="${ASC_KEY_FILE/#\~/$HOME}"  # Expand ~ in path
BUILD_NUMBER=$(date +%Y%m%d%H%M)

BUNDLE_ID="com.sabotage.clearly"
ASC_API="https://api.appstoreconnect.apple.com/v1"

# ── Helper functions ─────────────────────────────────────────────────────────

base64url_encode() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

generate_jwt() {
  local iat exp header payload signing_input der_sig sig_hex
  iat=$(date +%s)
  exp=$((iat + 1200))

  header=$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$ASC_KEY_ID" | base64url_encode)
  payload=$(printf '{"iss":"%s","iat":%d,"exp":%d,"aud":"appstoreconnect-v1"}' \
    "$ASC_ISSUER_ID" "$iat" "$exp" | base64url_encode)

  signing_input="$header.$payload"

  # Sign with ES256 — openssl produces DER, JWT needs raw r||s
  der_sig=$(printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$ASC_KEY_FILE" -binary | xxd -p -c 256)

  # Parse DER: 30 <len> 02 <r_len> <r_hex> 02 <s_len> <s_hex>
  local rest="${der_sig:4}"  # skip 30 <len>
  local r_len=$((16#${rest:2:2}))
  local r_hex="${rest:4:$((r_len * 2))}"
  rest="${rest:$((4 + r_len * 2))}"
  local s_len=$((16#${rest:2:2}))
  local s_hex="${rest:4:$((s_len * 2))}"

  # Strip DER sign-padding (extra 00 byte when high bit is set), then pad to 32 bytes
  if [ $r_len -eq 33 ]; then r_hex="${r_hex:2}"; fi
  if [ $s_len -eq 33 ]; then s_hex="${s_hex:2}"; fi
  while [ ${#r_hex} -lt 64 ]; do r_hex="00$r_hex"; done
  while [ ${#s_hex} -lt 64 ]; do s_hex="00$s_hex"; done

  local signature
  signature=$(printf '%s' "${r_hex}${s_hex}" | xxd -r -p | base64url_encode)

  echo "$header.$payload.$signature"
}

# Call App Store Connect API. Usage: asc_api GET /path  or  asc_api POST /path '{"json":...}'
asc_api() {
  local method="$1" path="$2" body="${3:-}"
  local jwt response http_code body_content

  jwt=$(generate_jwt)

  if [ -n "$body" ]; then
    response=$(curl -sg -w "\n%{http_code}" -X "$method" "${ASC_API}${path}" \
      -H "Authorization: Bearer $jwt" \
      -H "Content-Type: application/json" \
      -d "$body")
  else
    response=$(curl -sg -w "\n%{http_code}" -X "$method" "${ASC_API}${path}" \
      -H "Authorization: Bearer $jwt" \
      -H "Content-Type: application/json")
  fi

  http_code=$(echo "$response" | tail -1)
  body_content=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ge 400 ]]; then
    echo "❌ API error ($http_code) on $method $path" >&2
    echo "$body_content" >&2
    echo "" >&2
    echo "The build is already uploaded. Complete submission manually at https://appstoreconnect.apple.com" >&2
    exit 1
  fi

  echo "$body_content"
}

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

echo "🍎 Building Clearly v$VERSION (build $BUILD_NUMBER) for App Store..."

# Clean build
rm -rf build
mkdir -p build

# ── 1. Strip Sparkle keys from Info.plist (in place, restored later) ─────────
# Run each delete independently so missing keys don't abort the script under set -e.
cp Clearly/Info.plist build/Info-Original.plist
for key in SUFeedURL SUPublicEDKey SUEnableInstallerLauncherService; do
  /usr/libexec/PlistBuddy -c "Delete :$key" Clearly/Info.plist 2>/dev/null || true
done

# ── 2. Generate project.yml without Sparkle or ClearlyCLI ───────────────────
# The ClearlyCLI helper is stripped from App Store builds: as a sandboxed helper
# bundled at Contents/Resources/Helpers/ClearlyCLI it cannot read the main
# app's container, and App Store Review rejects non-sandboxed nested executables.
# Direct-download users still get it via release.sh.
sed \
  -e '/^  Sparkle:$/,/from:/d' \
  -e '/- package: Sparkle/d' \
  -e 's|Clearly/Clearly.entitlements|Clearly/Clearly-AppStore.entitlements|' \
  project.yml | \
awk '
  # Drop the ClearlyCLI target block (it is the last target in project.yml).
  /^  ClearlyCLI:/ { skip_target = 1 }
  skip_target { next }
  # Drop the postCompileScripts block inside the Clearly target.
  # It ends at the next 4-space-indented key (e.g. "    settings:").
  /^    postCompileScripts:/ { skip_postcompile = 1; next }
  skip_postcompile && /^    [a-zA-Z]/ { skip_postcompile = 0 }
  skip_postcompile { next }
  # Drop the ClearlyCLI dependency entry plus its indented children (embed, etc).
  /^      - target: ClearlyCLI/ { skip_cli_dep = 1; next }
  skip_cli_dep && /^        / { next }
  skip_cli_dep { skip_cli_dep = 0 }
  { print }
' > build/project-appstore.yml

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

# Verify iCloud entitlements survived Xcode archive/export
scripts/verify-entitlements.sh build/export-appstore/Clearly.app

# ── 6. Restore Info.plist and Xcode project (with Sparkle) ──────────────────
echo "🔄 Restoring Sparkle project..."
mv build/Info-Original.plist Clearly/Info.plist
xcodegen generate

echo "✅ Uploaded Clearly v$VERSION (build $BUILD_NUMBER) to App Store Connect."

# ── 7. Submit to App Review via App Store Connect API ────────────────────────
echo "📡 Submitting to App Review..."

# Get internal app ID
APP_ID=$(asc_api GET "/apps?filter[bundleId]=$BUNDLE_ID&fields[apps]=bundleId" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])")
echo "   App ID: $APP_ID"

# Poll for build processing
echo "   Waiting for build $BUILD_NUMBER to finish processing..."
BUILD_ID=""
POLL_TIMEOUT=900  # 15 minutes
POLL_INTERVAL=30
ELAPSED=0

while [ -z "$BUILD_ID" ]; do
  if [ "$ELAPSED" -ge "$POLL_TIMEOUT" ]; then
    echo "❌ Timed out waiting for build to process after ${POLL_TIMEOUT}s."
    echo "   The build is uploaded. Complete submission manually at https://appstoreconnect.apple.com"
    exit 1
  fi

  BUILD_ID=$(asc_api GET "/builds?filter[app]=$APP_ID&filter[version]=$BUILD_NUMBER&filter[processingState]=VALID&fields[builds]=version" | \
    python3 -c "import sys,json; d=json.load(sys.stdin)['data']; print(d[0]['id'] if d else '')")

  if [ -z "$BUILD_ID" ]; then
    sleep "$POLL_INTERVAL"
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
    echo "   Still processing... (${ELAPSED}s elapsed)"
  fi
done
echo "   Build ready: $BUILD_ID"

# Check for existing draft version
VERSION_ID=$(asc_api GET "/apps/$APP_ID/appStoreVersions?filter[versionString]=$VERSION&filter[platform]=MAC_OS&fields[appStoreVersions]=versionString,appStoreState" | \
  python3 -c "
import sys,json
data = json.load(sys.stdin)['data']
drafts = [v for v in data if v['attributes'].get('appStoreState') in ('PREPARE_FOR_SUBMISSION', 'DEVELOPER_ACTION_NEEDED')]
print(drafts[0]['id'] if drafts else '')
")

if [ -n "$VERSION_ID" ]; then
  echo "   Using existing draft version: $VERSION_ID"
else
  # Create new version
  VERSION_ID=$(asc_api POST "/appStoreVersions" "{
    \"data\": {
      \"type\": \"appStoreVersions\",
      \"attributes\": {
        \"versionString\": \"$VERSION\",
        \"platform\": \"MAC_OS\"
      },
      \"relationships\": {
        \"app\": {
          \"data\": { \"type\": \"apps\", \"id\": \"$APP_ID\" }
        }
      }
    }
  }" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['id'])")
  echo "   Created version: $VERSION_ID"
fi

# Set "What's New" from changelog
WHATS_NEW=$(extract_changelog_markdown "$VERSION" "CHANGELOG.md")
if [ -n "$WHATS_NEW" ]; then
  # Get en-US localization ID
  LOC_ID=$(asc_api GET "/appStoreVersions/$VERSION_ID/appStoreVersionLocalizations?fields[appStoreVersionLocalizations]=locale" | \
    python3 -c "
import sys,json
data = json.load(sys.stdin)['data']
en = [l for l in data if l['attributes']['locale'].startswith('en')]
print(en[0]['id'] if en else '')
")

  if [ -n "$LOC_ID" ]; then
    WHATS_NEW_JSON=$(printf '%s' "$WHATS_NEW" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")
    asc_api PATCH "/appStoreVersionLocalizations/$LOC_ID" "{
      \"data\": {
        \"type\": \"appStoreVersionLocalizations\",
        \"id\": \"$LOC_ID\",
        \"attributes\": {
          \"whatsNew\": $WHATS_NEW_JSON
        }
      }
    }" > /dev/null
    echo "   Updated \"What's New\" text."
  fi
fi

# Attach build to version
asc_api PATCH "/appStoreVersions/$VERSION_ID/relationships/build" "{
  \"data\": { \"type\": \"builds\", \"id\": \"$BUILD_ID\" }
}" > /dev/null
echo "   Attached build to version."

# Submit for review — uses the new reviewSubmissions API.
# The old appStoreVersionSubmissions endpoint was retired; it now returns
# 403 FORBIDDEN_ERROR with "The resource ... does not allow 'CREATE'".
# New flow: create a reviewSubmission, attach the version as an item, then
# PATCH the submission with submitted=true.

# Reuse any existing in-flight submission for this platform, or create one.
REVIEW_SUBMISSION_ID=$(asc_api GET "/reviewSubmissions?filter[app]=$APP_ID&filter[platform]=MAC_OS&filter[state]=READY_FOR_REVIEW,UNRESOLVED_ISSUES&fields[reviewSubmissions]=state" | \
  python3 -c "
import sys,json
data = json.load(sys.stdin)['data']
print(data[0]['id'] if data else '')
")

if [ -z "$REVIEW_SUBMISSION_ID" ]; then
  REVIEW_SUBMISSION_ID=$(asc_api POST "/reviewSubmissions" "{
    \"data\": {
      \"type\": \"reviewSubmissions\",
      \"attributes\": { \"platform\": \"MAC_OS\" },
      \"relationships\": {
        \"app\": { \"data\": { \"type\": \"apps\", \"id\": \"$APP_ID\" } }
      }
    }
  }" | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['id'])")
  echo "   Created review submission: $REVIEW_SUBMISSION_ID"
else
  echo "   Using existing review submission: $REVIEW_SUBMISSION_ID"
fi

# Attach the version as a submission item (idempotent — skip if already present).
EXISTING_ITEM=$(asc_api GET "/reviewSubmissions/$REVIEW_SUBMISSION_ID/items?fields[reviewSubmissionItems]=appStoreVersion&include=appStoreVersion" | \
  python3 -c "
import sys,json
d = json.load(sys.stdin)
for item in d.get('data', []):
    rel = item.get('relationships', {}).get('appStoreVersion', {}).get('data') or {}
    if rel.get('id') == '$VERSION_ID':
        print(item['id']); break
")

if [ -z "$EXISTING_ITEM" ]; then
  asc_api POST "/reviewSubmissionItems" "{
    \"data\": {
      \"type\": \"reviewSubmissionItems\",
      \"relationships\": {
        \"appStoreVersion\": { \"data\": { \"type\": \"appStoreVersions\", \"id\": \"$VERSION_ID\" } },
        \"reviewSubmission\": { \"data\": { \"type\": \"reviewSubmissions\", \"id\": \"$REVIEW_SUBMISSION_ID\" } }
      }
    }
  }" > /dev/null
  echo "   Attached version to review submission."
fi

# Flip the submission to submitted=true to send it to App Review.
asc_api PATCH "/reviewSubmissions/$REVIEW_SUBMISSION_ID" "{
  \"data\": {
    \"type\": \"reviewSubmissions\",
    \"id\": \"$REVIEW_SUBMISSION_ID\",
    \"attributes\": { \"submitted\": true }
  }
}" > /dev/null

echo "✅ Clearly v$VERSION submitted for App Review!"
echo "   Track status at: https://appstoreconnect.apple.com"
