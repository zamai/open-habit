# Open Habit verification

This document separates reproducible automated checks from behavior that requires provisioned Apple devices or accounts.

## Automated checks

The domain suite covers storage, synchronization semantics, streak and calendar calculations, import and export validation, deletion, concurrency, and shared-data projection:

```sh
swift test --package-path OpenHabitCore
```

The CI test entry point also exercises the app integration, widget rendering, deletion confirmation, and deterministic Shared Habit join flows on an iOS Simulator:

```sh
bash scripts/ci/test.sh
```

The import runner stages synthetic fixtures in a disposable Simulator and verifies the exported and restored data exactly:

```sh
bash scripts/ci/test-import.sh
```

`HABITKIT_TEST_FILE` and `HABITKIT_ORPHAN_TEST_FILE` may be used locally for additional compatibility checks. Those files can contain private user data and must never be committed, attached to issues, or included in test artifacts shared publicly.

## Simulator limits

Simulator builds intentionally use local storage instead of live private-database synchronization. The deterministic Shared Habit join fixture validates navigation and local choices but stops before CloudKit acceptance. A successful Simulator build therefore does not establish production iCloud, push-notification, invitation, or signing behavior.

## Signed-device acceptance

Before a release, verify the following with maintainer-controlled test accounts and synthetic data:

1. Install and reinstall on two devices using the same Apple Account; confirm initial seeding and private iCloud recovery.
2. Make offline changes on both devices, reconnect, and confirm Completions, notes, ordering, archive, deletion, and restore converge.
3. Create and accept fresh Shared Habit invitations between two different Apple Accounts. Verify progress synchronization, leaving, removal, and stopping sharing.
4. Exercise widget configuration and actions with the app terminated and networking unavailable.
5. Run every Shortcut action, including historical dates and future-date rejection.
6. Inspect iOS 17 fallback appearance, Dynamic Type, VoiceOver, Dark Mode, iPad multitasking, emoji rendering, and date changes around midnight and time-zone transitions.
7. Confirm unavailable-account, quota, and synchronization error messages without recording invitation URLs, member identities, or user data in logs.

## Release verification

A successful archive or upload is not the same as a working release. Confirm that the processed build is assigned to every configured internal and external TestFlight group, complete Beta App Review when required, and record any remaining external-testing state. Follow the current [release process](releases.md); the [version 1.0 submission record](app-store-submission.md) is retained for history.

For import/export coverage and fixture details, see [Data format verification](data-format/README.md#verification).
