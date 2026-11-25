#!/bin/bash
# Archive in Xcode Cloud (current Xcode, Apple-managed signing) and distribute to every TestFlight group.
set -euo pipefail
umask 077

if [[ $# -lt 1 || $# -gt 2 || -z "$1" ]]; then
  echo "Usage: $0 'What to test in this build' [branch]" >&2
  exit 1
fi
export WHAT_TO_TEST="$1"
cd "$(dirname "$0")/../.."
BRANCH="${2:-$(git branch --show-current)}"

git fetch -q origin "$BRANCH" || { echo "Branch $BRANCH is not on GitHub; push it first." >&2; exit 1; }
if [[ -z "${2:-}" ]]; then
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "Uncommitted changes would not be in the cloud build; commit and push first." >&2
    exit 1
  fi
  if [[ "$(git rev-parse HEAD)" != "$(git rev-parse "origin/$BRANCH")" ]]; then
    echo "Local $BRANCH differs from origin/$BRANCH; push or pull first." >&2
    exit 1
  fi
fi

CONFIG="${OPEN_HABIT_RELEASE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/open-habit/release.json}"
if [[ ! -f "$CONFIG" ]]; then
  echo "Local release configuration is missing: $CONFIG" >&2
  exit 1
fi
RELEASE_DIR=$(mktemp -d /tmp/open-habit-cloud.XXXXXX)
KEY_PATH="$RELEASE_DIR/AuthKey.p8"
cleanup() {
  rm -rf "$RELEASE_DIR"
  unset ASC_PRIVATE_KEY
}
trap cleanup EXIT

export ASC_KEY_ID="$(op read --no-newline "$(jq -er '.key_id' "$CONFIG")")"
export ASC_ISSUER_ID="$(op read --no-newline "$(jq -er '.issuer_id' "$CONFIG")")"
op read --no-newline "$(jq -er '.private_key' "$CONFIG")" > "$KEY_PATH"
export ASC_PRIVATE_KEY="$(< "$KEY_PATH")"
unlink "$KEY_PATH"
export SSL_CERT_FILE="${SSL_CERT_FILE:-/etc/ssl/cert.pem}"
export GITHUB_STEP_SUMMARY="$RELEASE_DIR/summary.md"

echo "Publishing $BRANCH ($(git rev-parse --short "origin/$BRANCH")) through Xcode Cloud"
python3 scripts/ci/wait-testflight.py --xcode-cloud "$BRANCH"
