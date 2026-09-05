#!/bin/bash
set -euo pipefail
swift test --package-path OpenHabitCore
DEVICE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; print(next(d["udid"] for runtime,devices in json.load(sys.stdin)["devices"].items() if "iOS" in runtime for d in devices if d["name"].startswith("iPhone")))')
xcodebuild -project OpenHabit.xcodeproj -scheme OpenHabit -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath "$RUNNER_TEMP/tests" -resultBundlePath "$RUNNER_TEMP/tests.xcresult" -only-testing:OpenHabitTests test
