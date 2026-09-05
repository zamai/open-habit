#!/bin/bash
set -euo pipefail
umask 077
SIGNING_DIR=$(mktemp -d "$RUNNER_TEMP/signing.XXXXXX")
KEYCHAIN="$SIGNING_DIR/signing.keychain-db"
cleanup() {
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  rm -rf "$SIGNING_DIR"
}
trap cleanup EXIT
export SIGNING_DIR
printf '%s' "$ASC_PRIVATE_KEY" > "$SIGNING_DIR/AuthKey.p8"
printf '%s' "$SIGNING_P12" | base64 --decode > "$SIGNING_DIR/signing.p12"
security create-keychain -p "$SIGNING_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$SIGNING_PASSWORD" "$KEYCHAIN"
security import "$SIGNING_DIR/signing.p12" -P "$SIGNING_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple: -k "$SIGNING_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" login.keychain-db
PROFILE_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
mkdir -p "$PROFILE_DIR"
printf '%s' "$APP_PROFILE" | base64 --decode > "$PROFILE_DIR/open-habit.mobileprovision"
printf '%s' "$WIDGET_PROFILE" | base64 --decode > "$PROFILE_DIR/open-habit-widgets.mobileprovision"
# Scope each profile to its target; the extension has a different bundle identifier.
python3 - <<'PY'
from pathlib import Path
p=Path('project.yml');s=p.read_text()
for bundle,profile in [('com.alex.openhabit','Open Habit CI App Store'),('com.alex.openhabit.widgets','Open Habit Widgets CI App Store')]:
 line='        PRODUCT_BUNDLE_IDENTIFIER: '+bundle+'\n'
 assert line in s
 s=s.replace(line,line+'        CODE_SIGN_STYLE: Manual\n        CODE_SIGN_IDENTITY: Apple Distribution\n        PROVISIONING_PROFILE_SPECIFIER: '+profile+'\n',1)
p.write_text(s)
PY
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate
# Start after local build 3; retries receive a fresh build number.
BUILD_NUMBER="$((${GITHUB_RUN_NUMBER} + 3)).${GITHUB_RUN_ATTEMPT}"
VERSION=$(sed -n "s/.*MARKETING_VERSION: '\(.*\)'/\1/p" project.yml)
if [[ "$GITHUB_REF" == refs/tags/v* ]]; then
  VERSION="${GITHUB_REF#refs/tags/v}"
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Use a vMAJOR.MINOR.PATCH tag'; exit 1; }
fi
xcodebuild -project OpenHabit.xcodeproj -scheme OpenHabit -configuration Release -destination 'generic/platform=iOS' -archivePath "$RUNNER_TEMP/OpenHabit.xcarchive" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" MARKETING_VERSION="$VERSION" archive
python3 - <<'PY'
import plistlib,os
from pathlib import Path
options=plistlib.loads(Path('scripts/release/ExportOptions.plist').read_bytes())
options.update(signingStyle='manual',signingCertificate='Apple Distribution',provisioningProfiles={'com.alex.openhabit':'Open Habit CI App Store','com.alex.openhabit.widgets':'Open Habit Widgets CI App Store'})
Path(os.environ['SIGNING_DIR'],'ExportOptions.plist').write_bytes(plistlib.dumps(options))
PY
xcodebuild -exportArchive -archivePath "$RUNNER_TEMP/OpenHabit.xcarchive" -exportPath "$RUNNER_TEMP/export" -exportOptionsPlist "$SIGNING_DIR/ExportOptions.plist" -authenticationKeyPath "$SIGNING_DIR/AuthKey.p8" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" -allowProvisioningUpdates
python3 scripts/ci/wait-testflight.py "$BUILD_NUMBER"
