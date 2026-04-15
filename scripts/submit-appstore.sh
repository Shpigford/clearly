#!/bin/bash
set -euo pipefail

# Usage: ./scripts/submit-appstore.sh <version>
#
# Submits an already-uploaded and version-attached App Store build for review
# using the reviewSubmissions API. Useful when release-appstore.sh's upload +
# attach succeeded but the final submit step failed (e.g. deprecated endpoint),
# or for re-submitting a draft version manually.
#
# Assumes: the build is uploaded, a draft appStoreVersion exists for this
# version string with the build already attached, and "What's New" is set.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

VERSION="${1:?Usage: ./scripts/submit-appstore.sh <version>}"
ASC_KEY_ID="${ASC_KEY_ID:?Set ASC_KEY_ID in .env}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:?Set ASC_ISSUER_ID in .env}"
ASC_KEY_FILE="${ASC_KEY_FILE:?Set ASC_KEY_FILE in .env}"
ASC_KEY_FILE="${ASC_KEY_FILE/#\~/$HOME}"

BUNDLE_ID="com.sabotage.clearly"
ASC_API="https://api.appstoreconnect.apple.com/v1"

base64url_encode() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

generate_jwt() {
  local iat exp header payload signing_input der_sig
  iat=$(date +%s); exp=$((iat + 1200))
  header=$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$ASC_KEY_ID" | base64url_encode)
  payload=$(printf '{"iss":"%s","iat":%d,"exp":%d,"aud":"appstoreconnect-v1"}' "$ASC_ISSUER_ID" "$iat" "$exp" | base64url_encode)
  signing_input="$header.$payload"
  der_sig=$(printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$ASC_KEY_FILE" -binary | xxd -p -c 256)
  local rest="${der_sig:4}"
  local r_len=$((16#${rest:2:2})); local r_hex="${rest:4:$((r_len * 2))}"
  rest="${rest:$((4 + r_len * 2))}"
  local s_len=$((16#${rest:2:2})); local s_hex="${rest:4:$((s_len * 2))}"
  if [ $r_len -eq 33 ]; then r_hex="${r_hex:2}"; fi
  if [ $s_len -eq 33 ]; then s_hex="${s_hex:2}"; fi
  while [ ${#r_hex} -lt 64 ]; do r_hex="00$r_hex"; done
  while [ ${#s_hex} -lt 64 ]; do s_hex="00$s_hex"; done
  local signature
  signature=$(printf '%s' "${r_hex}${s_hex}" | xxd -r -p | base64url_encode)
  echo "$header.$payload.$signature"
}

asc_api() {
  local method="$1" path="$2" body="${3:-}" jwt response http_code body_content
  jwt=$(generate_jwt)
  if [ -n "$body" ]; then
    response=$(curl -sg -w "\n%{http_code}" -X "$method" "${ASC_API}${path}" \
      -H "Authorization: Bearer $jwt" -H "Content-Type: application/json" -d "$body")
  else
    response=$(curl -sg -w "\n%{http_code}" -X "$method" "${ASC_API}${path}" \
      -H "Authorization: Bearer $jwt" -H "Content-Type: application/json")
  fi
  http_code=$(echo "$response" | tail -1)
  body_content=$(echo "$response" | sed '$d')
  if [[ "$http_code" -ge 400 ]]; then
    echo "❌ API error ($http_code) on $method $path" >&2
    echo "$body_content" >&2
    exit 1
  fi
  echo "$body_content"
}

echo "📡 Submitting Clearly v$VERSION for App Review..."

APP_ID=$(asc_api GET "/apps?filter[bundleId]=$BUNDLE_ID&fields[apps]=bundleId" | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['id'])")
echo "   App ID: $APP_ID"

VERSION_ID=$(asc_api GET "/apps/$APP_ID/appStoreVersions?filter[versionString]=$VERSION&filter[platform]=MAC_OS&fields[appStoreVersions]=versionString,appStoreState" | \
  python3 -c "
import sys,json
data = json.load(sys.stdin)['data']
drafts = [v for v in data if v['attributes'].get('appStoreState') in ('PREPARE_FOR_SUBMISSION', 'DEVELOPER_ACTION_NEEDED')]
print(drafts[0]['id'] if drafts else '')
")

if [ -z "$VERSION_ID" ]; then
  echo "❌ No draft version found for v$VERSION. Upload a build first with release-appstore.sh." >&2
  exit 1
fi
echo "   Version: $VERSION_ID"

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
else
  echo "   Version already attached: $EXISTING_ITEM"
fi

asc_api PATCH "/reviewSubmissions/$REVIEW_SUBMISSION_ID" "{
  \"data\": {
    \"type\": \"reviewSubmissions\",
    \"id\": \"$REVIEW_SUBMISSION_ID\",
    \"attributes\": { \"submitted\": true }
  }
}" > /dev/null

echo "✅ Clearly v$VERSION submitted for App Review!"
echo "   Track status at: https://appstoreconnect.apple.com"
