# Open Habit

Open Habit is an offline-first iPhone and iPad habit tracker designed around interactive Home Screen widgets, Shortcuts, iCloud sync, and portable user-owned data.

- [MVP product design](./docs/mvp.md)
- [Shared Habits design](./docs/shared-habits.md)
- [Domain language](./CONTEXT.md)
- [Architecture decisions](./docs/adr/)
- [Version 1.0 architecture review](./docs/architecture-review.md)

Open Habit is free to use and will be released as open source under the [MIT license](LICENSE). Everyone is welcome to contribute code, ideas, bug reports, documentation, and translations. The repository remains private during initial development; public source access will follow with the open-source release.

## Build and run

Open `OpenHabit.xcodeproj` in Xcode 26 or newer and run the **OpenHabit** scheme on an iPhone or iPad Simulator. The deployment target is iOS/iPadOS 17; native Liquid Glass controls are enabled on iOS 26 with material fallbacks on earlier versions.

The checked-in Xcode project is generated from `project.yml`. After changing target configuration, install XcodeGen and run `xcodegen generate`.

```sh
swift test --package-path OpenHabitCore
xcodebuild -project OpenHabit.xcodeproj -scheme OpenHabit \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGN_IDENTITY=- test
```

Keep ad-hoc signing enabled in Simulator: the app and widget need their App Group entitlements to access the same storage. `CODE_SIGNING_ALLOWED=NO` can compile the app but does not produce a working shared-container installation.

## Device and iCloud setup

The app and widget use the paid Apple Developer team `539QCPHM7F`. These identifiers are registered and provisioned (replace them consistently in `project.yml` and `SharedStore.swift` for another team):

- App: `com.alex.openhabit`
- Widget extension: `com.alex.openhabit.widgets`
- App Group: `group.com.alex.openhabit`
- CloudKit container: `iCloud.com.alex.openhabit`

App Groups and the private CloudKit container are enabled for both targets, and Push Notifications for the app. The app creates the `OpenHabit` custom record zone, its silent-push subscription, and `HabitEdit` records with a `payload` asset. The initial schema was deployed to production on September 5, 2026. Future schema changes must also be deployed before distributing builds that require them.

Simulator intentionally uses local storage and reports that live iCloud is unavailable. It seeds the starter dataset locally. Signed devices check the private database before seeding; a network or uncertain account error leaves a fresh dataset unseeded until a successful check, while still allowing manual habit creation and offline tracking.

## TestFlight

The App Store Connect listing is [Open Habit: Daily Tracker](https://appstoreconnect.apple.com/apps/6808947599/testflight), with the subtitle **Private habits. Small steps.** The installed app displays **Open Habit**.

Regenerate the project after changing `project.yml`. The publishing script queries App Store Connect and overrides `CURRENT_PROJECT_VERSION` with the next available build number. Follow the 1Password API authentication instructions in [AGENTS.md](AGENTS.md#testflight-releases) and add the three authentication flags to the commands below:

```sh
xcodegen generate
xcodebuild -project OpenHabit.xcodeproj -scheme OpenHabit \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath /tmp/OpenHabit.xcarchive -allowProvisioningUpdates archive
xcodebuild -exportArchive -archivePath /tmp/OpenHabit.xcarchive \
  -exportPath /tmp/OpenHabit-export \
  -exportOptionsPlist scripts/release/ExportOptions.plist \
  -allowProvisioningUpdates
```

The export command uploads to App Store Connect. Release verification assigns the processed build to every configured TestFlight tester group and submits it for Beta App Review when Apple requires it.

GitHub Actions runs the core, app, widget-rendering, deletion, and Shared Habit join tests for pull requests. Every successful push to `main` receives a unique build number, is signed with the `testflight` environment credentials, uploaded, assigned to every internal and external tester group, and submitted for Beta App Review when needed. An hourly reconciliation job retries external review if Apple already has another build in review. A matching release tag (for example, `v1.0.0` when `MARKETING_VERSION` is `1.0`) creates another TestFlight build and a draft GitHub Release after processing. The Files round-trip and SpringBoard widget-install tests stay local because they depend on a disposable Files container or persistent Home Screen state.

The App Store Connect API key must have the **App Manager** or **Admin** role so CI can add builds to the external group and submit them for Beta App Review.

The CI distribution certificate and profiles expire on September 5, 2027. Renew them before that date and replace the `SIGNING_P12`, `SIGNING_PASSWORD`, `APP_PROFILE`, and `WIDGET_PROFILE` environment secrets.

Before App Store submission, follow the remaining release gates in [App Store submission](docs/app-store-submission.md).

## Implementation

- `OpenHabitCore`: domain values, fixed local date keys, deterministic edit reconciliation, full JSON validation, and locked atomic persistence.
- `OpenHabit/App`: overview, habit editor, rolling year and month calendar, Day Notes, archived habits, settings, export and confirmed replacement restore.
- `OpenHabit/Shared`: shared storage, private CloudKit synchronization, App Intents, and reusable history/completion visuals.
- `OpenHabit/Widgets`: configured small single-Habit and medium three-Habit interactive widgets. Hold a widget and choose Edit Widget to assign active Habits. Missing or archived assignments stay visible as configuration placeholders.
- `OpenHabitTests`: integration tests exercising all four intents and the widget button intent against real shared storage.
- `OpenHabitUITests`: an English-language Simulator smoke test that installs the small widget if missing and verifies its configuration menu. It changes the test Simulator’s Home Screen layout.

Cloud synchronization exchanges UUID-addressed edits. Distinct additions merge, retries are idempotent, properties/notes/order use the latest timestamp (UUID breaks ties), archive is independent of property editing, and deletion tombstones prevent resurrection. Restore and Delete All Data create a new dataset generation; older offline edits cannot bring replaced data back. Deletion and replacement redact removed content from the journal and synchronize those redactions; only causality markers remain so old offline edits cannot resurrect it.

The app synchronizes on activation, after edits, during foreground polling, and on iCloud push notifications. Widget and Shortcut actions commit locally first and attempt synchronization afterward. Cloud errors never roll back a successful local completion. The first implementation enumerates the entire private zone on each sync; incremental tokens and compaction of causality markers can be added when real dataset sizes justify them.

See [verification notes](docs/verification.md) for what has been tested and what still needs provisioned devices.
