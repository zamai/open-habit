# Open Habit verification

## Shared Habits implementation (13 September 2026)

The first end-to-end implementation slice is present in the app. It includes the isolated shared data projection, local membership cache, cross-device membership records, Owner setup with fresh/full history, single-use Invitation creation, CloudKit share acceptance, Start New and Use Existing joining, the Members presentation, Member identity editing, Invitation cancellation, Member removal, leaving, and the Owner stopping sharing while preserving their local Habit.

The core suite verifies that the shared projection excludes Day Notes and note-only Habit Days, preserves local identity and organization when adopting a shared definition, assigns all ten palette colors, and orders the current Member before the Owner and join order. The app-hosted rendering suite covers the ten-Member phone layout. Core, application, and widget tests pass, and both Simulator and unsigned generic-device builds compile with Xcode 26.3. The generic-device build compiles the live CloudKit code path; the Simulator intentionally does not execute it. Shared records reuse the deployed `HabitEdit.payload` asset envelope, so this slice requires no Production schema change.

The following remain release blockers rather than inferred successes:

1. Exercise creation, Invitation delivery, acceptance, synchronization, leaving, removal, and stopping sharing on signed iOS 18-or-later devices using two different iCloud accounts.
2. Confirm the one-time URL behavior on iOS 18 through iOS 26. Xcode 26 currently imports the public iOS 18 URL accessor with iOS 26 availability, so the iOS 18–25 compatibility path calls that public Objective-C selector dynamically.
3. Inspect the Shared Habit, join, ten-Member, Dynamic Type, Dark Mode, and VoiceOver UI on devices. Automated rendering proves allocation, not usability.
4. Add provisioned-device regression checks showing private Habit sync, widgets, App Intents, backup, import, and restore remain unaffected by the shared record-name prefixes.

## Automated checks

Validated with Xcode 26.3 and the iOS 26.3 Simulator on 5 September 2026: 13 domain tests, two app-hosted integration/rendering tests, and one Home Screen UI test passed. Both final Simulator and unsigned device builds passed.

- The pure Swift domain suite covers starter seeding exactly once, target-1 and multi-target toggling, capped additions, concurrent merge and retry idempotency, nonnegative removals, current-target history presentation, daily and weekly Current Streak derivation, visible-month Completion totals, archive versus property edits, permanent-deletion visibility, restore generation isolation, fixed date keys, note/date validation, full-fidelity JSON round trips, unsupported versions, failed-transaction rollback, and 40 concurrent store writers.
- The widget rendering test produces native images at small and medium widget dimensions. Both images were inspected for row allocation and clipping.
- The application-hosted integration suite exercises the four Shortcut intents and the widget toggle against the App Group store. These tests create and tombstone only their own fixture Habit.
- Both Simulator and unsigned generic-device builds compile the application and widget extension. The latter includes the live CloudKit implementation.

## Live Simulator checks

- Fresh local setup loads exactly the three specified starter Habits, with one Water Completion.
- The Water control increments to three and then clears to zero.
- Habit creation, Habit Detail deep linking, count correction, and Day Note persistence work in the running app.
- Browser mirroring displays an actual live Simulator frame.
- A configured small widget updates Water from 0 to 1 without opening the app; its active-Habit configuration query resolves the shared app dataset.
- The iPad overview renders two columns at normal text sizes and switches to one column at accessibility sizes. Light, Dark, and largest accessibility text rendering were inspected.

## Remaining device acceptance

The Apple Developer team, App Group, and CloudKit container are now provisioned. These checks still require signed devices; a successful archive or TestFlight upload does not establish them:

1. Install on two devices on the same iCloud account. Verify first install versus reinstall seeding and recovery.
2. Disconnect both devices, add distinct Completions, reconnect, and verify counts and manual order converge. Repeat with concurrent notes, archive, deletion, and backup restore.
3. Verify widget configuration and button execution from Home Screen with the app terminated and networking disabled. Confirm a missing assignment becomes a placeholder.
4. Run all four actions from the Shortcuts app, including historical dates, future rejection, and progress result properties.
5. Check iOS 17 fallback appearance, actual-device emoji rendering, Dynamic Type, VoiceOver, iPad multitasking, and midnight/time-zone transitions.
6. Verify iCloud quota and account-unavailable messaging and silent push delivery.

## Distribution verification

On September 5, 2026, the Release archive for version 1.0 (1) passed and Xcode's CLI uploaded it successfully to App Store Connect app `6808947599`. Both archived provisioning profiles include the shared App Group and iCloud container under team `539QCPHM7F`. Xcode's distribution signing log confirms the uploaded app and widget use the Production CloudKit environment, and the app uses production APNs.

App Store Connect finished processing the build. The Internal Testers group shows **Testing**, one build, and one accepted tester (Alex's account). External Beta App Review was not submitted. Installation and runtime behavior on a physical device remain unverified.

CloudKit Console confirmed deployment of `HabitEdit` with a `payload` Asset field, and the type and field were read back in the Production environment. This establishes schema availability, not two-device synchronization behavior.

The available iOS 26.3 Simulator renders emoji as missing-glyph boxes even though their Unicode text is intact. This visual limitation remains to be checked on a device.

Deletion removes Habits and their days from the dataset, views, exports, and edit payloads after convergence. Redacted edit IDs and deletion tombstones remain solely to prevent old offline edits from resurrecting data. The domain suite verifies the removed Habit name and Day Note are absent from serialized journal payloads.

## Widget revision (build 2)

The small widget now shows 10 weeks with 4-point gaps, a top-right completion button, and a black background. The medium widget uses three explicitly bounded rows. Widget histories use a Canvas drawing instead of the app's hundreds of tile views and gestures, reducing the view tree sent to WidgetKit.

Both widget sizes passed app-hosted rendering and intent tests. Rendering checks require visible colored content in every row and a black outer margin. The real Simulator widget gallery rendered the medium preview; a Home Screen medium widget was configured with all three starter habits and its Exercise button changed the count from 0 to 1 without opening the app, then back to 0. The live browser mirror was inspected. The original physical-device blank state did not reproduce in Simulator, so build 2 still needs confirmation on the affected phone.

The signed Release archive is `/tmp/OpenHabit-2-final.xcarchive`, with app and widget version 1.0 (2). Xcode Organizer confirmed upload of 1.0 (2), and App Store Connect subsequently showed **Testing** for build 2 in the Internal Testers group. The CLI failed with “Failed to Use Accounts” while Organizer could use the signed-in account. Widget retest notes and the free/open-source MIT release description are saved in App Store Connect.

Build 1.0 (3) includes custom habit colors, the title beside its emoji, and removal of the Today panel from Habit Detail. The Release archive `/tmp/OpenHabit-3.xcarchive` passed with build number 3 in both app and widget. Organizer uploaded it on September 5, 2026. The 1Password App Store Connect key was then verified against Open Habit through the API: build `c4a3695e-2724-4d86-82bb-de62ca997eeb` is `VALID`, assigned to Internal Testers, and `IN_BETA_TESTING`, with automatic notification enabled. External state remains `READY_FOR_BETA_SUBMISSION`. Future releases should follow the API-first instructions in `AGENTS.md`.

GitHub Actions run [33990168840](https://github.com/zamai/open-habit/actions/runs/33990168840) completed the first end-to-end CI release on September 5, 2026. It passed 14 core tests and 2 signed Simulator integration/rendering tests, archived with the dedicated distribution certificate and profiles, uploaded build 1.0 (6.1), and waited until App Store Connect reported build `01831879-7409-4290-a450-6a51a9209caf` as `VALID`, assigned to Internal Testers, and `IN_BETA_TESTING`. The SpringBoard widget-install UI test remains local because its result depends on persistent Home Screen state.

## Captured UI

- [iPhone overview](screenshots/iphone-overview.png)
- [iPad Dark overview](screenshots/ipad-dark.png)
- [Small widget rendering](screenshots/small-widget.png)
- [Medium widget rendering](screenshots/medium-widget.png)
- [Configured widgets on Home Screen](screenshots/widgets-home-screen.png)

The widget images are native rendering-test captures at WidgetKit dimensions. Both sizes also have verified Home Screen interactions. The Home Screen UI smoke test requires an English-language Simulator and may add a small widget and enter Home Screen editing.

## Import/export verification

See [Data format verification](data-format/README.md#verification) for core and Files-based UI round-trip coverage, the reproducible disposable-Simulator command, and verification of the original HabitKit export.
