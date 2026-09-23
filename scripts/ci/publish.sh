#!/bin/bash
set -euo pipefail
umask 077
DESTINATION="${1:-testflight}"
if [[ "$DESTINATION" != "testflight" && "$DESTINATION" != "app-store" ]]; then
  echo "Usage: $0 [testflight|app-store]"
  exit 1
fi
VERSION=$(sed -n "s/.*MARKETING_VERSION: '\(.*\)'/\1/p" project.yml)
if [[ "$GITHUB_REF" == refs/tags/v* ]]; then
  TAG_VERSION="${GITHUB_REF#refs/tags/v}"
  if [[ "$TAG_VERSION" =~ ^([0-9]+\.[0-9]+(\.[0-9]+)?)-rc\.([1-9][0-9]*)$ ]]; then
    RELEASE_VERSION="${BASH_REMATCH[1]}"
    [[ "$DESTINATION" == "testflight" ]] || {
      echo "Release candidate tag $TAG_VERSION can only publish to TestFlight"
      exit 1
    }
  elif [[ "$TAG_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    RELEASE_VERSION="$TAG_VERSION"
    [[ "$DESTINATION" == "app-store" ]] || {
      echo "Stable tag $TAG_VERSION can only publish to the App Store"
      exit 1
    }
  else
    echo "Tag $TAG_VERSION must look like v1.2-rc.1, v1.2.3-rc.1, v1.2, or v1.2.3"
    exit 1
  fi
  [[ "$RELEASE_VERSION" == "$VERSION" || "$RELEASE_VERSION" == "$VERSION.0" ]] || {
    echo "Tag version $RELEASE_VERSION does not match MARKETING_VERSION $VERSION in project.yml"
    exit 1
  }
elif [[ "$DESTINATION" == "app-store" ]]; then
  echo "App Store publishing requires a stable release tag"
  exit 1
fi
SIGNING_DIR=$(mktemp -d "$RUNNER_TEMP/signing.XXXXXX")
KEYCHAIN="$SIGNING_DIR/signing.keychain-db"
cleanup() {
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  rm -rf "$SIGNING_DIR"
}
trap cleanup EXIT
export SIGNING_DIR
printf '%s' "$ASC_PRIVATE_KEY" > "$SIGNING_DIR/AuthKey.p8"
printf '%s' "$SIGNING_P12" | base64 -D > "$SIGNING_DIR/signing.p12"
security create-keychain -p "$SIGNING_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$SIGNING_PASSWORD" "$KEYCHAIN"
security import "$SIGNING_DIR/signing.p12" -P "$SIGNING_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
security set-key-partition-list -S apple-tool:,apple: -k "$SIGNING_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" login.keychain-db
PROFILE_DIR="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
mkdir -p "$PROFILE_DIR"
printf '%s' "$APP_PROFILE" | base64 -D > "$PROFILE_DIR/open-habit.mobileprovision"
printf '%s' "$WIDGET_PROFILE" | base64 -D > "$PROFILE_DIR/open-habit-widgets.mobileprovision"
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
# Continue from the highest build already known to App Store Connect.
BUILD_NUMBER="$(python3 scripts/ci/wait-testflight.py --next-build-number)"
xcodebuild -project OpenHabit.xcodeproj -scheme OpenHabit -configuration Release -destination 'generic/platform=iOS' -archivePath "$RUNNER_TEMP/OpenHabit.xcarchive" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" MARKETING_VERSION="$VERSION" archive
python3 - <<'PY'
import plistlib,os
from pathlib import Path
options=plistlib.loads(Path('scripts/release/ExportOptions.plist').read_bytes())
options.update(signingStyle='manual',signingCertificate='Apple Distribution',provisioningProfiles={'com.alex.openhabit':'Open Habit CI App Store','com.alex.openhabit.widgets':'Open Habit Widgets CI App Store'})
Path(os.environ['SIGNING_DIR'],'ExportOptions.plist').write_bytes(plistlib.dumps(options))
PY
xcodebuild -exportArchive -archivePath "$RUNNER_TEMP/OpenHabit.xcarchive" -exportPath "$RUNNER_TEMP/export" -exportOptionsPlist "$SIGNING_DIR/ExportOptions.plist" -authenticationKeyPath "$SIGNING_DIR/AuthKey.p8" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" -allowProvisioningUpdates
if [[ "$DESTINATION" == "app-store" ]]; then
  python3 scripts/ci/wait-testflight.py "$BUILD_NUMBER" --processing-only
  python3 scripts/ci/submit-app-store.py "$VERSION" "$BUILD_NUMBER"
else
  python3 scripts/ci/wait-testflight.py "$BUILD_NUMBER"
fi
