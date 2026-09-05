## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for `zamai/open-habit`. See `docs/agents/issue-tracker.md`.

### Triage labels

The repository uses the five canonical triage label names without overrides. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository. See `docs/agents/domain.md`.

## TestFlight releases

Use the App Store Connect API key in 1Password before attempting UI automation: vault `Agents`, item `ZamaNom - App Store Connect Publishing` (`snudnovpmg542sng4g27l74tu4`), fields `key_id`, `issuer_id`, and `private_key`. Retrieve it with `op`, verify access to Open Habit (`6808947599`, team `539QCPHM7F`), and pass it to `xcodebuild` using `-authenticationKeyPath`, `-authenticationKeyID`, and `-authenticationKeyIssuerID`. Keep the private key in a temporary file with mode 600, remove it afterward, and never print or commit credentials. Use CLI/API for upload and processing checks; use Xcode Organizer only if API authentication is unavailable. Verify the processed build is available to Internal Testers.

GitHub Actions uses the `testflight` environment for `main` and `v*`. Its distribution certificate and both App Store profiles expire September 5, 2027; renew them and replace the four signing secrets before expiry. Pull requests and `main` run deterministic app tests; the SpringBoard widget-install smoke test remains local.
