## Before starting work

Always pull the latest `main` before starting any task: run `git fetch origin main` and fast-forward (`git pull --ff-only origin main` on `main`, or rebase a worktree onto `origin/main`). Do not start work on a stale checkout.

Commit to `main` and push; no branches or PRs unless Alex asks. A parallel session works in a worktree and lands its commits on `main`.

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for `zamai/open-habit`. See `docs/agents/issue-tracker.md`.

### Triage labels

The repository uses the five canonical triage label names without overrides. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository. See `docs/agents/domain.md`.

## TestFlight releases

Before publishing to TestFlight or setting up local signing, read [docs/releases.md](docs/releases.md) for the publishing command, credential configuration, signing setup, and distribution checks.

Release credentials are maintained outside the repository. Never print, commit, or add them to documentation. For local publishing, pass the App Store Connect key to `xcodebuild` with `-authenticationKeyPath`, `-authenticationKeyID`, and `-authenticationKeyIssuerID`; keep the private key in a mode-600 temporary file and remove it afterward.

When asked to publish to TestFlight, distribute the newest processed build to every configured TestFlight tester group, internal and external. Submit it for Beta App Review when Apple requires review for external testing. Do not call the release complete after checking only Internal Testers: read back the build's group relationships and verify that every configured group is assigned, then report the external review/testing state if external access is not active yet.

TestFlight builds are archived in Xcode Cloud. Publish a pushed branch with `scripts/release/publish-cloud.sh 'What to test' [branch]` or the manually started **TestFlight (Xcode Cloud)** GitHub Actions workflow (see docs/releases.md). The Watch app is embedded in the iOS archive, so there is no separate watchOS release. No push or tag builds or publishes the app. Run `bash scripts/ci/test.sh` locally before committing app changes. The SpringBoard widget-install smoke test remains local.

App Store Connect: use `~/Code/agent-home-personal/bin/asc` (`asc --help`); don't write ad-hoc API scripts.
