# Open Habit MVP

Status: agreed product design.

## Product promise

Open Habit is a private, offline-first iPhone and iPad habit tracker for people who want to record progress with almost no friction and retain ownership of their data. Its defining interaction is completing a Habit directly from the Home Screen.

Open Habit will be free to use and released as open source under the MIT license, with contributions welcome from everyone. The repository remains private during development; publishing the source is a later release step, not an MVP dependency.

## Observable MVP outcome

A person can create and organize multiple Habits, record each one from the app or a Home Screen widget, inspect and correct their history, track an optional daily or weekly streak, attach a short note to a day, automate tracking with Shortcuts, synchronize through their private iCloud account, and export or restore all data as JSON. Every tracking flow continues to work without a network connection or an Open Habit account.

## Platform

- Native iOS and iPadOS application targeting iOS 17 and iPadOS 17 or later.
- iPhone receives a purpose-built layout. iPad uses an adaptive version of the same experience.
- No dedicated macOS, watchOS, Android, or web application in the MVP.
- The product does not operate an account system, API, or hosted user-data service.

## Habit semantics

### Habit definition

Each Habit has:

- A stable identifier.
- A required name of at most 60 characters.
- Exactly one emoji.
- An optional one-sentence description of at most 160 characters.
- A color selected from a curated palette.
- A Daily Target from 1 through 99.
- An optional daily or weekly Streak Goal. A weekly goal requires between one and seven completed Habit Days per calendar week.
- One immutable creation date.
- A manual position in the overview.
- An active or archived state.

Only positive Habits are supported. Streak Goals do not schedule particular days or mark empty days as failed. There are no due days, rest days, monthly goals, or avoidance Habits.

### Habit Days and Daily Progress

- Every local calendar date can be viewed as a Habit Day, including dates before creation and dates while the Habit was archived.
- A date with no Completions is simply empty. Open Habit never labels it failed, missed, or overdue.
- A Habit Day's date is fixed using the device's local calendar date when data is recorded. Traveling later must not move existing data to another date.
- The day rolls over at local midnight. A custom rollover time is outside the MVP.
- The current Daily Target is applied when presenting every past and present Habit Day.
- Changing the Daily Target can therefore change how historical tiles appear.
- Daily Progress is derived from the Completion count and current Daily Target; it is never stored independently.
- Open Habit has no distinct overachievement state. Counts at or above the current Daily Target have the same complete presentation, and quick logging cannot add more once the current target is reached.

### Archiving and deletion

- Archiving removes a Habit from the current overview and widgets while retaining its history.
- Restoring an Archived Habit returns it to the current overview. The original creation date remains unchanged.
- Dates during an archived interval remain visually indistinguishable from any other empty dates.
- Permanent deletion removes the Habit, its Completions, and its Day Notes from all synchronized devices after explicit confirmation.

## Completion interactions

The completion control follows the supplied HabitKit reference:

- For a Daily Target of 1, the control is a checkbox that toggles between 0 and 1.
- For a Daily Target greater than 1, the control begins as a plus surrounded by a segmented progress ring.
- Each tap adds one Completion and fills one segment until the Daily Target is reached.
- At the Daily Target, the control becomes a checkbox.
- Tapping that completed checkbox toggles the Habit Day back to 0.
- The control never increments beyond the current Daily Target.

An in-app long press on the completion control opens this menu:

- Undo latest Completion today.
- Mark today complete by setting its count to the current Daily Target.
- Mark yesterday complete by setting its count to the current Daily Target.
- Edit today's Habit Day.
- Edit the Habit.
- Archive the Habit.
- Delete the Habit, followed by destructive-action confirmation.

Widget long press remains owned by iOS and does not show this menu.

## Starter Habits

A genuinely new, empty dataset starts with three real, editable Habits:

| Habit | Emoji | Color | Daily Target | Description | Initial progress |
| --- | --- | --- | ---: | --- | --- |
| Exercise | 🏃 | Orange | 1 | Move your body for at least twenty minutes. | 0 |
| Drink the f★cking water | 💧 | Blue | 3 | Why do I need habit tracking for drinking water? | 1 Completion today |
| Read five pages | 📖 | Green | 1 | Five pages is enough to keep the story moving. | 0 |

A dismissible message explains that these are examples and may be edited, reordered, archived, or deleted. They are created only after determining that neither local storage nor iCloud contains an existing dataset. They are never recreated after deletion or restoration.

## Main overview

The main screen takes its density and composition from HabitKit's full-width card overview while using Open Habit's own styling and assets.

- A Settings button sits at the top left.
- An Add Habit button sits at the top right.
- There are no category filters, statistics buttons, or view-mode controls.
- iPhone shows one full-width Habit card per row.
- Wider iPad layouts adapt to two card columns.
- A card contains the emoji, name, one-line description, rolling history grid, and completion control.
- The card does not show streak or goal chips.
- Tapping noninteractive card content opens Habit Detail.
- Pressing, holding, and dragging a card reorders Habits with haptic feedback.
- The manual order synchronizes through iCloud.

### History tiles

The same tile language is used in the overview, Habit Detail, and widgets:

- No Completions: dim empty tile.
- Below the current Daily Target: Habit color at intensity proportional to progress.
- At or above the current Daily Target: solid Habit color.
- Today: thin outline.
- Day Note present: small dot indicator.

Color must not be the only accessible indication of state.

## Create and edit Habit

Creation and editing use a modal screen containing:

- A field accepting exactly one emoji.
- Required name, up to 60 characters.
- Optional single-line description, up to 160 characters.
- A curated color palette.
- Daily Target stepper from 1 through 99.
- A live preview of the completion control.
- An optional Streak Goal with Daily or Weekly period and a completed-days target for Weekly goals.
- Create or Save action.
- Archive and Delete actions when editing an existing Habit.

Custom icon sets, arbitrary colors, schedules, categories, reminders, and advanced options are excluded.

## Habit Detail

Habit Detail follows the supplied HabitKit reference and contains:

- Emoji, name, and description.
- Daily Target, optional Current Streak, and current-week progress for a Weekly Streak Goal.
- Month Total for the calendar month currently visible.
- A GitHub-style rolling year grid.
- A month calendar for selecting an exact date.
- The selected Habit Day's Completion count, current Daily Target, and Day Note.
- Edit Habit access.

The user may edit the Completion count and Day Note for today or any past date. Future dates are read-only.

Tapping a calendar day selects it. Pressing and holding a day opens the Habit Day editor. The editor contains a count control and one optional multiline plain-text Day Note of at most 500 characters. Notes have no formatting, tags, or attachments.

Best-streak statistics, charts, sharing, and year-in-review are excluded.

## Home Screen widgets

Widgets preserve the size, spacing, density, and content allocation of the supplied HabitKit references while using Open Habit's visual identity.

### Small single-Habit widget

- Configured for one selected active Habit.
- Shows emoji and name in the header.
- Shows today's count, but never displays the Daily Target or a `count / target` fraction.
- Shows a compact recent-history grid.
- Includes the completion control with the same plus, segmented-progress, checkbox, and toggle behavior as the app.
- Tapping noninteractive content opens the selected Habit in the app.

### Medium three-Habit widget

- Shows exactly three selected active Habits in three equal rows.
- Each row preserves the reference widget's spacing and allocation.
- Each row shows the Habit emoji, recent-history tiles, today's count, and completion control without displaying the Daily Target.
- Tapping a row's completion control updates that Habit.
- Tapping other row content opens that Habit in the app.
- If an assigned Habit is archived or deleted, its row becomes a clear configuration placeholder instead of silently substituting another Habit.

Widget completion persists locally before reporting success and refreshes without opening the app or requiring network access. iOS owns the widget's long-press behavior for widget configuration.

Large widgets, Lock Screen widgets, year-grid widgets, and multiple presentation styles are excluded.

## Shortcuts and App Intents

Open Habit exposes:

1. **Add Completions** — active Habit and amount, defaulting to 1.
2. **Remove Completions** — Habit and amount, defaulting to 1.
3. **Get Today's Progress** — returns count, Daily Target, and whether the target is met.
4. **Set Day Note** — Habit, date, and text.

An optional date allows explicit historical automation. Future dates are rejected. Additions stop at the current Daily Target and removals stop at zero. Widget buttons reuse the same domain operations as these intents.

Native webhooks are deferred. A user may combine an Open Habit Shortcut action with an HTTP action in Apple's Shortcuts application.

## Local data and iCloud

- Local storage is the immediate source for the app, widgets, and App Intents.
- Every feature remains usable while offline.
- When the user has an available iCloud account, the local dataset synchronizes automatically through the user's private CloudKit database.
- No Open Habit account or hosted user-data service exists.
- Settings reports `Synced`, `Syncing`, or a specific actionable problem such as unavailable iCloud or insufficient quota.
- Reinstalling the app or installing it on another iPhone or iPad signed into the same iCloud account restores and synchronizes the dataset.
- Open Habit describes iCloud as synchronization and reinstall recovery, not a versioned backup against accidental edits or deletions.

Concurrent edits reconcile with these observable rules:

- Distinct Completion additions merge without losing progress, up to the current Daily Target.
- Completion removals never produce a negative count.
- Habit properties, manual ordering, and a Day Note use the latest edit.
- Archive wins over older edits while preserving history.
- Confirmed permanent deletion propagates to all devices.
- The MVP does not expose a manual conflict-resolution interface.

The repository's architectural rationale is recorded in [ADR 0001](./adr/0001-keep-data-local-and-sync-through-icloud.md).

## JSON backup and restore

Only Open Habit's native JSON format is supported in the MVP. CSV and HabitKit-specific imports are deferred.

### Export

Export produces one versioned, full-fidelity JSON document containing:

- Format version and export timestamp.
- Application settings.
- Habit ordering.
- Active and Archived Habits with stable identifiers and creation dates.
- Names, emoji, descriptions, colors, Daily Targets, and optional Streak Goals.
- Completion data and Day Notes.

The export contains no iCloud account or device identifiers.

### Restore

Import is presented as **Restore from Backup**:

1. Parse and validate the entire document without changing current data.
2. Show a summary of the backup's contents.
3. Require explicit confirmation that the current dataset will be replaced.
4. Replace the dataset atomically.
5. Synchronize the restored result through iCloud so other devices converge.

Any parsing, validation, or write failure leaves the original dataset unchanged. Importing an unsupported future format version produces an explanatory error rather than a partial restore.

## Settings

The Settings screen contains only:

- iCloud sync status and actionable errors.
- Appearance: System, Light, or Dark.
- First day of week: System Default, Monday, or Sunday.
- Archived Habits.
- Export Backup.
- Restore from Backup.
- About Open Habit.
- Delete All Data, with explicit confirmation and a warning that synchronized data will also be removed.

The source-code link is added when the repository becomes public.

## Design and accessibility

- HabitKit is a composition and density reference, not a source of code, trademarks, icons, or other assets.
- Open Habit supports System, Light, and Dark appearances from the MVP.
- Habit colors retain adequate contrast in each appearance.
- Text supports Dynamic Type without clipping important controls.
- Interactive targets meet Apple's minimum comfortable target size.
- VoiceOver identifies the Habit, today's count, Daily Target, and the action each completion control will perform.
- Progress remains understandable without color alone.
- Increment, toggle, drag, and destructive actions provide appropriate haptic feedback.

## Explicit non-goals

- Hosted accounts or user-data service.
- Web, Android, watchOS, or dedicated macOS clients.
- Native webhooks.
- Avoidance or quit Habits.
- Schedules, reminders, notifications, rest days, or monthly goals.
- Overachievement as a state or quick-log behavior.
- Categories, multiple overview modes, aggregate statistics beyond Month Total and Current Streak, or charts.
- Sharing cards, social features, coaching, or gamification.
- Rich-text notes, multiple notes per Habit Day, tags, or attachments.
- CSV or third-party backup import.
- Large, Lock Screen, or alternative-style widgets.

## MVP acceptance criteria

1. A fresh install with no local or iCloud dataset creates the three specified Starter Habits exactly once, including one Water Completion today.
2. A person can create, edit, reorder, archive, restore, and permanently delete multiple Habits.
3. Target-1 controls toggle `0 ↔ 1`; higher targets show segmented progress, stop at the target, and toggle from completed back to zero.
4. The in-app long-press menu exposes all seven agreed quick actions, with confirmation before deletion.
5. Main-screen, detail, and widget tiles consistently show empty, partial, complete, today, and note-present states.
6. A person can correct counts and attach or edit a Day Note for today or any past date, but not a future date.
7. Changing a Daily Target immediately re-evaluates the presentation of all historical Habit Days without storing separate success states.
8. The small widget operates one Habit and the medium widget operates exactly three, with completion occurring without launching the app.
9. All four App Intents work through Shortcuts and enforce the same date and count rules as the app.
10. Tracking works with networking and iCloud unavailable; when iCloud returns, two devices converge according to the documented conflict rules.
11. Reinstalling on the same iCloud account recovers the synchronized dataset without recreating Starter Habits.
12. JSON export contains the complete dataset, and a valid restore atomically replaces it while an invalid restore changes nothing.
13. A Habit may derive a Daily or Weekly Current Streak, and Habit Detail shows the Month Total for its visible calendar month.
