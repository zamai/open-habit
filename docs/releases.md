# Releases

Open Habit is archived in Xcode Cloud, not on a GitHub-hosted macOS runner. The **TestFlight (Xcode Cloud)** GitHub Actions workflow is started by hand. It runs on a Linux runner and drives Xcode Cloud through the App Store Connect API, so it adds no macOS runner cost. A push, pull request or tag does not build or publish. A scheduled workflow retries Beta App Review for builds already uploaded to TestFlight.

Run `bash scripts/ci/test.sh` locally before committing app changes. The Files round-trip and SpringBoard widget-install tests require separate local checks.

## Xcode Cloud TestFlight publishing

Xcode Cloud is the default way to publish. Any branch that is pushed to GitHub can be published. From this Mac:

```sh
scripts/release/publish-cloud.sh 'What to test in this build'            # current branch
scripts/release/publish-cloud.sh 'What to test in this build' some-branch
```

Without a branch argument, the script refuses to run while the checkout has uncommitted changes or differs from `origin/<branch>`, because Xcode Cloud builds what GitHub has. It reads the App Store Connect key from 1Password, like the local publish.

From GitHub, run the **TestFlight (Xcode Cloud)** workflow from the Actions tab, or:

```sh
gh workflow run testflight.yml --ref some-branch -f what_to_test='What to test in this build'
```

The `branch` input defaults to the branch the run uses. It must be set explicitly only to build a different branch than the workflow file comes from.

`scripts/ci/wait-testflight.py --xcode-cloud <branch>` starts the Xcode Cloud workflow named `Release` (override with `XCODE_CLOUD_WORKFLOW`) on that branch. It waits for the archive and upload, then waits for processing. It assigns every configured TestFlight group and sets What to Test. It submits Beta App Review when Apple requires it. It uses the `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_PRIVATE_KEY` secrets in the `testflight` environment.

Xcode Cloud selects the Xcode version, so Apple's newer-SDK upload requirements do not depend on the macOS version of a local Mac. Signing is Apple-managed automatic signing; the 1Password identity and local profiles are not used. Each run spends compute hours from the 25 hours per month included with the Apple Developer Program. The workflow only archives, so a release costs minutes, not the full UI test suite.

One-time setup, done by the Account Holder or an Admin:

1. In Xcode, choose Integrate › Create Workflow, select the OpenHabit iOS app, and grant Xcode Cloud access to the `zamai/open-habit` GitHub repository.
2. Name the workflow `Release` and set Environment › Xcode Version to Latest Release. The only start condition is Manual Start on any branch; remove Branch Changes so pushes do not spend compute hours. Add an Archive action for iOS with the `OpenHabit` scheme and Distribution Preparation set to App Store Connect. TestFlight (Internal Testing Only) builds cannot reach external testers. Add a TestFlight Internal Testing post-action; the workflow script adds the external groups.
3. In App Store Connect, go to Xcode Cloud › Settings › Build Number and set the next build number above the highest uploaded build.

## Local TestFlight publishing (fallback)

This archives with the Xcode installed on this Mac. From April 2027, App Store Connect rejects uploads built with an SDK older than iOS 27, so use Xcode Cloud unless it is unavailable.


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
