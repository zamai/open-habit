# Open Habit JSON data

Open Habit exports its own snapshot format. [Version 3 schema](open-habit-v3.schema.json) and [synthetic example](open-habit-v3.example.json) describe the public contract. The format identifier is `open-habit`; version numbers belong to that format, not to HabitKit.

- New exports use version 3. Versions 1 and 2 remain readable. Version 1 timestamps are seconds since 2001-01-01 UTC; versions 2 and 3 use ISO 8601 UTC strings with nine fractional-second digits. Unsupported versions and mismatched identifiers are rejected.
- Habits and categories are ordered arrays with stable UUIDs. Categories retain their names, source icon names, creation dates, and membership through `categoryIDs`. Category filtering and editing are not implemented yet.
- Habit Day keys are uppercase `HABIT-UUID/YYYY-MM-DD`. A day contains a nonnegative integer count and a note of up to 500 Swift Characters. A missing day is empty. Counts may exceed the current target; importing does not clamp history.
- Habit names allow up to 60 Swift Characters; descriptions are single-line, up to 160; an emoji must be one emoji grapheme. JSON Schema character-length rules cannot precisely express these grapheme constraints, so the app performs final validation.
- Streak goals use the current daily threshold. A weekly target counts completed days, not individual occurrences. All history is interpreted using current targets.
- Appearance, week start, example dismissal state, archive states, custom colors, creation times, notes, order, and categories are retained in native backups. The internal sync journal and device/account identifiers are excluded.

## Import and restore

Settings → Import offers **Open Habit import** and **HabitKit data import**. Both parse and validate the whole file before showing a preview. No changes occur until confirmation.

Import adds new Habit IDs and new category IDs. Matching Habit IDs are skipped as a whole, preserving all existing properties, notes, and counts. Matching names do not cause a match. Categories with an existing ID keep their current definition. Previously deleted Habit IDs are also skipped in the current dataset generation. Repeated or simultaneous offline imports cannot double daily counts. This is an add-only migration, not ongoing reconciliation with another app.

Both import formats offer **Replace all data**. For a native Open Habit backup, replacement restores settings and ordering as well as habits, history, and categories. For a HabitKit export, it restores the converted habits, history, goals, and categories with default Open Habit settings. Replacement creates a new synchronization generation so old offline edits cannot resurrect the previous dataset. Use updated app builds on all synchronized devices: older builds cannot understand the new import journal operation or the version 3 backup.

A local recovery backup is written under the same store lock before an import changes data, before replacement, and before Delete All Data. A failure to write recovery prevents the change. Settings → Recovery Backups can restore, export, or swipe-delete these files. Recovery files survive Delete All Data, do not sync to other devices, and are removed when the app is uninstalled. They are retained until explicitly deleted.

## HabitKit version 2

The importer accepts positive incremental habits with a single current interval of type `none`, `day`, or `week`. Daily targets and daily/weekly streak goals transfer separately. Categories and assignments transfer, including categories without members. Habit order uses `orderIndex` with original file order to break ties.

Completion dates are derived from each timestamp using its recorded `timezoneOffsetInMinutes`, independent of the current device zone. Zero counts and history before habit creation are valid. Category assignments for Habits absent from the export are skipped with a preview warning. Missing Habit references in completions or intervals, invalid category assignments for included Habits, duplicate record IDs, invalid dates/counts, unsupported goal modes, and invalid field lengths reject the file without partial writes.

Multiple records for the same Habit Day require an explicit choice in the preview: latest record, largest amount, or sum. None is assumed to be HabitKit's authoritative behavior. Distinct notes for the same day are joined with blank lines and disclosed; notes that would exceed 500 characters reject the file rather than truncating text.

The preview lists icon-to-emoji and color substitutions, historical goal interval loss, reminder omission, and changes to exceeding-goal behavior. Inverse habits and custom-value tracking are rejected because they cannot be faithfully represented. Original completion IDs/times and interval history are not part of Open Habit's daily snapshot, so a native export is not a byte-for-byte HabitKit backup. Keep the source file.

## Verification

`swift test --package-path OpenHabitCore` exercises an on-disk create/import/edit/export/delete/restore cycle, archived habits, Unicode notes, categories, goals, preferences, order, duplicate resolution, concurrent imports, deletion, and recovery-write failures.

The checked-in HabitKit fixture is synthetic. To verify the original personal attachment without committing it:

```sh
HABITKIT_TEST_FILE=/absolute/path/habitkit_export.json swift test --package-path OpenHabitCore
```

The private-file test explicitly skips when that environment variable is absent. It checks the supplied export's known 9 habits, 591 Habit Days, 12 categories, 5 weekly goals, and 2 ambiguous days, then round-trips all supported duplicate resolutions.

Set `HABITKIT_ORPHAN_TEST_FILE` to the later export with 5 Habits and 3 stale category assignments to verify that the importer warns about those assignments, preserves 540 Habit Days, and round-trips its one ambiguous day.

`OpenHabitUITests/ImportUITests` exercises the actual file picker and create/import/note/export/delete/reimport UI. Run only on a disposable, English-language Simulator. Before the run, install the test app and copy `OpenHabitCore/Tests/OpenHabitCoreTests/Fixtures/habitkit-synthetic.json` into its Documents directory. Simulator tests do not establish physical-device iCloud synchronization.

For a disposable Simulator run with fixture staging, exact export/restore comparison, and cleanup, use `scripts/ci/test-import.sh` (requires an installed iOS runtime supporting iPhone 17). Set `HABITKIT_TEST_FILE` to include the private original-file UI round-trip; otherwise that optional UI case skips before changing data. Artifacts, including exported snapshots, are retained in the temporary directory printed by the runner. Set `IMPORT_RUNTIME` to a CoreSimulator runtime identifier to test a specific iOS version; by default the runner uses the newest available runtime. `IMPORT_SIMCTL` can point to the installed CoreSimulator `simctl` binary when Xcode's launcher is blocked by unfinished component installation.

### Verified September 13, 2026

- All 27 core tests passed with the matching original export recovered from iCloud Drive Downloads; no core tests skipped.
- Both existing hosted app tests passed (App Intents and widget layout).
- Both Files-based UI round-trips passed on a disposable iPhone 17 / iOS 26.3 Simulator: the synthetic fixture and the original HabitKit export, including explicit duplicate-day choices, note entry, export, Delete All Data, and native restoration.
- The original file contained 9 habits, 593 completion records spanning 591 Habit Days, 12 categories, 5 category assignments, and 5 weekly goals. An independent source comparison checked habit identities/names/descriptions/archive states/targets/goals/assignments, category ordering/names/icons, and every converted date/count pair. With the deliberately chosen sum interpretation, the source and converted counts both totaled 583.
- Independent comparison of the final UI-exported JSON against the restored on-disk journal found an exact dataset match: 17 habits, 597 Habit Days, 13 categories, and 3 notes, including settings, ordering, IDs, dates, goals, colors, and counts. This combines starter habits, newly created test habits, the synthetic fixture, and the original export.
- The original source file's SHA-256 was unchanged after verification. Personal JSON is not committed to the repository.
- The published synthetic native example validates against the version 3 JSON Schema.
- Simulator font rendering showed fallback glyphs for emoji in both newly created and imported habits; Unicode content itself passed round-trip comparison. Physical-device iCloud sync and release distribution were not exercised.
- HabitKit's authoritative interpretation of the two ambiguous days is still unknown. The importer requires a choice; tests exercised all three choices in core and the sum choice in UI.
