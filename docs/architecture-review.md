# Architecture review

Historical snapshot: reviewed September 22, 2026 for the version 1.0 App Store candidate. Findings and open risks below describe that point in time, not the current release state. For current release steps, see [Releases](releases.md) and [Verification](verification.md).

## Shape of the app

Open Habit uses four practical boundaries:

1. `OpenHabitCore` owns the data model, validation, import conversion, journal merge rules, streak calculations, and local transactions. It has no SwiftUI, WidgetKit, or CloudKit dependency.
2. `OpenHabit/App` owns presentation and `AppModel`, the main coordinator for local state, synchronization, imports, and Shared Habits.
3. `OpenHabit/Shared` contains code used by the app and widget: App Group storage, intents, widget content, private CloudKit sync, and Shared Habit CloudKit sync.
4. `OpenHabit/Widgets` contains only the WidgetKit entry points and configuration.

This is an appropriate structure for the current app. The domain can be tested without Apple services, while the app and widget reuse the same storage and action implementations.

## Review findings

### Sharing cache ownership

The cache in `shared-habits.json` could outlive its local Habit. Cleanup lived in `AppModel`, so stale metadata was visible to deletion and replacement guards before every path had reconciled it. This caused an apparently empty account to behave as though a Shared Habit still existed.

`SharingStore` now reconciles its cache with the current `Dataset` whenever the app loads or synchronizes. Orphaned entries are removed from disk. The UI coordinator no longer implements this storage invariant.

### Import safety

HabitKit import validates identifiers and references before conversion, requires one active compatible goal interval per Habit, bounds counts and time-zone offsets, and exposes duplicate same-day records for an explicit resolution. The three supplied exports pass the domain suite, and the September 22 export passes the full Files round trip.

Optional interval end dates and weekly-goal display no longer use force unwraps. These were not the reported failure, but removing them keeps malformed incoming data on the validation path instead of a potential crash path.

### Persistence and synchronization

Local changes use a locked atomic journal transaction in the shared App Group container. Merge operations are deterministic and restore generations prevent old offline edits from resurrecting replaced data. Private CloudKit records and Shared Habit records have separate namespaces and projections.

The current full-zone private sync is intentionally simple. Incremental tokens and journal compaction would add state and recovery cases without solving a current dataset-size problem.

### UI composition

`SharedHabitViews.swift` is the largest source file, but it contains one end-to-end feature and shares local state across its three-step join flow. Splitting it for file size alone would increase indirection. `AppModel` remains a coordinator; storage cleanup was removed from it rather than introducing another application layer.

### Release and privacy

There are no third-party SDKs, analytics, ads, purchases, or developer accounts. Both the app and widget carry the privacy manifest. File timestamp access is declared because recovery backups display modification dates. Store copy now describes the product as it exists and does not promise public source access while the repository is private.

## Release risks recorded at review time

- Shared Habit creation, acceptance, progress synchronization, leaving, and owner cleanup still need a final two-account physical-device pass.
- A Home Screen widget action with the app terminated still needs a provisioned-device pass.
- App Review contact details and the App Privacy questionnaire still need completion in App Store Connect.
- App Store screenshots are uploaded at the current required iPhone and iPad sizes.

The [version 1.0 submission record](app-store-submission.md) shows which release gates were subsequently completed. [Verification](verification.md) contains the ongoing signed-device checks.
