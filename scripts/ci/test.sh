#!/bin/bash
set -euo pipefail
swift test --package-path OpenHabitCore
TEST_ARTIFACTS=${RUNNER_TEMP:-$(mktemp -d /tmp/open-habit-tests.XXXXXX)}
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; print(next(d["udid"] for runtime,devices in json.load(sys.stdin)["devices"].items() if "iOS" in runtime for d in devices if d["name"].startswith("iPhone")))')
xcodebuild -project OpenHabit.xcodeproj -scheme OpenHabit -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath "$TEST_ARTIFACTS/tests" -resultBundlePath "$TEST_ARTIFACTS/tests.xcresult" -only-testing:OpenHabitTests -only-testing:OpenHabitUITests/SharedHabitJoinUITests -only-testing:OpenHabitUITests/DeleteConfirmationUITests test
