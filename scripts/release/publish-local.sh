#!/bin/bash
set -euo pipefail
umask 077

if [[ $# != 1 || -z "$1" ]]; then
  echo "Usage: $0 'What to test in this build'" >&2
  exit 1
fi
export WHAT_TO_TEST="$1"
cd "$(dirname "$0")/../.."

CONFIG="${OPEN_HABIT_RELEASE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/open-habit/release.json}"
if [[ ! -f "$CONFIG" ]]; then
  echo "Local release configuration is missing: $CONFIG" >&2
  echo "See docs/releases.md for setup." >&2
  exit 1
fi
command -v op >/dev/null
command -v jq >/dev/null
RELEASE_DIR=$(mktemp -d /tmp/open-habit-release.XXXXXX)
KEY_PATH="$RELEASE_DIR/AuthKey.p8"
cleanup() {
  if [[ -f "$KEY_PATH" ]]; then unlink "$KEY_PATH"; fi
  unset ASC_PRIVATE_KEY
}
trap cleanup EXIT

export ASC_KEY_ID="$(op read --no-newline "$(jq -er '.key_id' "$CONFIG")")"
export ASC_ISSUER_ID="$(op read --no-newline "$(jq -er '.issuer_id' "$CONFIG")")"
op read --no-newline "$(jq -er '.private_key' "$CONFIG")" > "$KEY_PATH"
chmod 600 "$KEY_PATH"
export ASC_PRIVATE_KEY="$(< "$KEY_PATH")"
export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/cert.pem}"
export GITHUB_STEP_SUMMARY="$RELEASE_DIR/summary.md"

VERSION=$(sed -n "s/.*MARKETING_VERSION: '\(.*\)'/\1/p" project.yml)
BUILD_NUMBER=$(python3 scripts/ci/wait-testflight.py --next-build-number)
echo "Publishing Open Habit $VERSION ($BUILD_NUMBER) from $(git rev-parse --short HEAD)"
echo "Release artifacts: $RELEASE_DIR"

AUTH=(-authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" -allowProvisioningUpdates)
xcodebuild -quiet -project OpenHabit.xcodeproj -scheme OpenHabit -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$RELEASE_DIR/OpenHabit.xcarchive" \
  -derivedDataPath "$RELEASE_DIR/DerivedData" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "${AUTH[@]}" archive
xcodebuild -quiet -exportArchive -archivePath "$RELEASE_DIR/OpenHabit.xcarchive" \
  -exportPath "$RELEASE_DIR/export" -exportOptionsPlist scripts/release/ExportOptions-local.plist \
  "${AUTH[@]}"
python3 scripts/ci/wait-testflight.py "$BUILD_NUMBER"
