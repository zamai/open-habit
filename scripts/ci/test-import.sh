#!/bin/bash
# Run on a disposable Simulator; no personal habit store is touched.
set -euo pipefail
cd "$(dirname "$0")/../.."
IMPORT_ARTIFACTS=$(mktemp -d /tmp/open-habit-import-tests.XXXXXX)
simctl() {
  if [[ -n "${IMPORT_SIMCTL:-}" ]]; then "$IMPORT_SIMCTL" "$@"; else xcrun simctl "$@"; fi
}
IMPORT_RUNTIME=${IMPORT_RUNTIME:-$(simctl list runtimes -j | python3 -c 'import json,sys; print(max((r for r in json.load(sys.stdin)["runtimes"] if r["isAvailable"] and "iOS" in r["identifier"]), key=lambda r: tuple(map(int,r["version"].split("."))))["identifier"])')}
IMPORT_DEVICE=$(simctl create 'Open Habit Import Tests' com.apple.CoreSimulator.SimDeviceType.iPhone-17 "$IMPORT_RUNTIME")
cleanup() { simctl shutdown "$IMPORT_DEVICE" >/dev/null 2>&1 || true; simctl delete "$IMPORT_DEVICE" >/dev/null 2>&1 || true; }
trap cleanup EXIT
simctl boot "$IMPORT_DEVICE"
simctl bootstatus "$IMPORT_DEVICE" -b
xcodebuild -project OpenHabit.xcodeproj -scheme OpenHabit -destination "platform=iOS Simulator,id=$IMPORT_DEVICE" -derivedDataPath "$IMPORT_ARTIFACTS/build" -only-testing:OpenHabitUITests/ImportUITests build-for-testing > "$IMPORT_ARTIFACTS/build.log" 2>&1
simctl install "$IMPORT_DEVICE" "$IMPORT_ARTIFACTS/build/Build/Products/Debug-iphonesimulator/OpenHabit.app"
IMPORT_CONTAINER=$(simctl get_app_container "$IMPORT_DEVICE" com.alex.openhabit data)
cp OpenHabitCore/Tests/OpenHabitCoreTests/Fixtures/habitkit-synthetic.json "$IMPORT_CONTAINER/Documents/"
if [[ -n "${HABITKIT_TEST_FILE:-}" ]]; then cp "$HABITKIT_TEST_FILE" "$IMPORT_CONTAINER/Documents/habitkit-personal.json"; fi
echo "Import test artifacts: $IMPORT_ARTIFACTS"
xcodebuild -project OpenHabit.xcodeproj -scheme OpenHabit -destination "platform=iOS Simulator,id=$IMPORT_DEVICE" -derivedDataPath "$IMPORT_ARTIFACTS/build" -resultBundlePath "$IMPORT_ARTIFACTS/results.xcresult" -parallel-testing-enabled NO -collect-test-diagnostics never -testLanguage en -testRegion US -only-testing:OpenHabitUITests/ImportUITests test-without-building

IMPORT_CONTAINER=$(simctl get_app_container "$IMPORT_DEVICE" com.alex.openhabit data)
IMPORT_GROUP=$(simctl get_app_container "$IMPORT_DEVICE" com.alex.openhabit group.com.alex.openhabit)
cp -R "$IMPORT_CONTAINER/Documents" "$IMPORT_ARTIFACTS/exported"
cp "$IMPORT_GROUP/OpenHabit/journal.json" "$IMPORT_ARTIFACTS/restored-journal.json"
swiftc OpenHabitCore/Sources/OpenHabitCore/*.swift scripts/ci/verify-import.swift -o "$IMPORT_ARTIFACTS/verify-import"
"$IMPORT_ARTIFACTS/verify-import" "$IMPORT_ARTIFACTS/exported" "$IMPORT_ARTIFACTS/restored-journal.json"
