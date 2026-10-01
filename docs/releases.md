# Releases

iOS build and publishing jobs in GitHub Actions are disabled to avoid hosted-runner costs. A push, pull request, tag, or manual workflow dispatch does not build or publish Open Habit. The remaining scheduled workflow only retries Beta App Review for builds already uploaded to TestFlight.

Run `bash scripts/ci/test.sh` locally before committing app changes. The Files round-trip and SpringBoard widget-install tests require separate local checks.

TestFlight and App Store publishing are paused until local distribution signing is configured. The Mac needs an Apple Distribution identity and matching provisioning profiles; the App Store Connect API key alone cannot sign a release archive. Keep credentials outside this repository and follow the release-credential rules in `AGENTS.md`.

After a local upload, verify that the newest processed build is assigned to every configured internal and external TestFlight group. Submit it for Beta App Review if Apple requires review, and report whether external testing is active.

The prior RC and stable tag automation is inactive. Tags do not trigger TestFlight or App Store submissions.
