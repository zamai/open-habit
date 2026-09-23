## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for `zamai/open-habit`. See `docs/agents/issue-tracker.md`.

### Triage labels

The repository uses the five canonical triage label names without overrides. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository. See `docs/agents/domain.md`.

## TestFlight releases

Release credentials are maintained outside the repository. Never print, commit, or add them to documentation. For local publishing, pass the App Store Connect key to `xcodebuild` with `-authenticationKeyPath`, `-authenticationKeyID`, and `-authenticationKeyIssuerID`; keep the private key in a mode-600 temporary file and remove it afterward.

When asked to publish to TestFlight, distribute the newest processed build to every configured TestFlight tester group, internal and external. Submit it for Beta App Review when Apple requires review for external testing. Do not call the release complete after checking only Internal Testers: read back the build's group relationships and verify that every configured group is assigned, then report the external review/testing state if external access is not active yet.

GitHub Actions uses the protected `testflight` environment for `main` and `v*`. Pull requests and `main` run deterministic app tests; the SpringBoard widget-install smoke test remains local.
