#!/bin/bash
# Runs the core, app and UI test suites. The app and UI suites use a throwaway
# iOS Simulator that is deleted on exit, so data left on a reused simulator
# never affects the result. Set SIMULATOR_ID to use an existing simulator instead.
set -euo pipefail

STAGE=setup
SIMULATOR=""
CREATED_SIMULATOR=""
SUMMARY_PRINTED=0
FAILED=()
RUN_DIR=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/open-habit-tests.XXXXXX")

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [ -n "$CREATED_SIMULATOR" ]; then
    xcrun simctl shutdown "$CREATED_SIMULATOR" >/dev/null 2>&1 || true
    xcrun simctl delete "$CREATED_SIMULATOR" >/dev/null 2>&1 || true
  fi
  rm -rf "$RUN_DIR/DerivedData"
  if [ "$SUMMARY_PRINTED" -eq 0 ]; then
    echo "TESTS FAILED: $STAGE (exit $status after ${SECONDS}s)"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Runs one suite and records a failure instead of stopping, so every suite reports.
run_suite() {
  local name=$1
  shift
  STAGE=$name
  echo "=== $name"
  if ! "$@"; then
    FAILED+=("$name")
  fi
}

if [ -n "${SIMULATOR_ID:-}" ]; then
  SIMULATOR=$SIMULATOR_ID
else
  # Same device type and runtime as the first available iPhone simulator.
  read -r DEVICE_TYPE RUNTIME < <(
    xcrun simctl list devices available -j |
      python3 -c 'import json,sys; print(*next((d["deviceTypeIdentifier"], runtime) for runtime, devices in json.load(sys.stdin)["devices"].items() if "iOS" in runtime for d in devices if d["name"].startswith("iPhone")))'
  )
  CREATED_SIMULATOR=$(xcrun simctl create "OpenHabit-tests-${RUN_DIR##*.}" "$DEVICE_TYPE" "$RUNTIME")
  SIMULATOR=$CREATED_SIMULATOR
  echo "Simulator $SIMULATOR ($DEVICE_TYPE, $RUNTIME); results in $RUN_DIR"
fi

XCODEBUILD=(
  xcodebuild
  -project OpenHabit.xcodeproj
  -scheme OpenHabit
  -destination "platform=iOS Simulator,id=$SIMULATOR"
  -derivedDataPath "$RUN_DIR/DerivedData"
)

run_suite core swift test --package-path OpenHabitCore

STAGE=build
"${XCODEBUILD[@]}" -resultBundlePath "$RUN_DIR/build.xcresult" build-for-testing

run_suite app "${XCODEBUILD[@]}" -resultBundlePath "$RUN_DIR/app.xcresult" \
  -only-testing:OpenHabitTests test-without-building
run_suite ui "${XCODEBUILD[@]}" -resultBundlePath "$RUN_DIR/ui.xcresult" \
  -only-testing:OpenHabitUITests/SharedHabitJoinUITests \
  -only-testing:OpenHabitUITests/DeleteConfirmationUITests \
  -only-testing:OpenHabitUITests/HabitDetailUITests \
  test-without-building

SUMMARY_PRINTED=1
if [ "${#FAILED[@]}" -eq 0 ]; then
  echo "TESTS PASSED (core, app, ui) in ${SECONDS}s"
else
  FAILED_LIST=$(IFS=,; echo "${FAILED[*]}")
  echo "TESTS FAILED: ${FAILED_LIST//,/, } after ${SECONDS}s (result bundles in $RUN_DIR)"
  exit 1
fi
