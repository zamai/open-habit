# Releases

iOS build and publishing jobs in GitHub Actions are disabled to avoid hosted-runner costs. A push, pull request, tag, or manual workflow dispatch does not build or publish Open Habit. The remaining scheduled workflow only retries Beta App Review for builds already uploaded to TestFlight.

Run `bash scripts/ci/test.sh` locally before committing app changes. The Files round-trip and SpringBoard widget-install tests require separate local checks.

## Local TestFlight publishing

The release uses the existing iOS Distribution identity from the Agents 1Password vault and the installed App Store profiles for the app, widgets, and Watch app. The certificate expires October 1, 2027. No existing certificates are revoked.

Run:

```sh
/Users/alex/Code/open-habit/scripts/release/publish-local.sh 'What to test in this build'
```

The command reads the signing identity and App Store Connect credentials from 1Password, creates a disposable encrypted signing keychain with a random per-run password, and verifies non-interactive signing before archiving. It then chooses the next build number, archives locally, uploads, waits for processing, and assigns every configured TestFlight group. It submits Beta App Review when required. It does not submit an App Store release.

Configuration lives outside the repository at `$XDG_CONFIG_HOME/open-habit/release.json`, defaulting to `$HOME/.config/open-habit/release.json`. It contains `key_id`, `issuer_id`, `private_key`, `signing_private_key`, and `signing_certificate` fields with immutable `op://<vault-id>/<item-id>/<field>` references, not credential values. `OPEN_HABIT_RELEASE_CONFIG` can override its path. The Agents service-account environment must be available. The temporary API private-key file is mode 600 and removed on exit. The signing private key is piped directly into the temporary keychain and imported as non-extractable. The keychain permits the Apple signing tools to sign without a dialog, is placed first in the keychain search list for the release, and is deleted on success, failure, or interruption. The original login keychain and its access rules are unchanged; cleanup removes the temporary keychain from the search list while preserving other entries.

`ExportOptions-local.plist` selects the temporary distribution identity and the three `Open Habit … Local App Store` profiles, avoiding cloud signing. On another Mac, configure the immutable vault references and install those profiles before publishing. The signing helper restores the identity automatically; the release does not depend on unlocking a login keychain or approving a macOS dialog. Renew the identity and profiles before expiration. Keep credentials outside this repository and follow `AGENTS.md`.

After a local upload, verify that the newest processed build is assigned to every configured internal and external TestFlight group. Submit it for Beta App Review if Apple requires review, and report whether external testing is active.

The prior RC and stable tag automation is inactive. Tags do not trigger TestFlight or App Store submissions.
