# Shared Habits

Status: agreed product and implementation design.

## Product promise

Shared Habits let a small private group practise the same Habit together without turning Open Habit into a social network. Every Member participates, records only their own Completions, and can see the other Members' shared progress. Day Notes and personal organization remain private.

Sharing is local-first and uses CloudKit Sharing. Open Habit operates no account system or synchronization server, but the feature still relies on Apple's iCloud servers and requires every Member to use an iCloud account. It is therefore server-free for Open Habit, not literal peer-to-peer synchronization.

## Observable outcome

An Owner can open an existing Habit to as many as nine invited friends. Each friend accepts a private, single-use Invitation, chooses a Member Name, and either starts a new local Habit or connects an existing one. The Habit Detail screen then presents every Member's progress together. Members continue tracking while offline; shared progress catches up after a later user action or app refresh.

The first implementation targets Apple platforms only. Android has no native CloudKit SDK. A future Android client could use CloudKit Web Services, but would still require iCloud authentication and substantial custom integration; it is not part of this design.

## Group model

- One Shared Habit contains exactly one Habit definition and at most ten Members, including the Owner.
- Every Member participates. There are no observers, followers, or read-only subscribers.
- One CloudKit share represents one Shared Habit. Sharing another Habit with the same people requires another set of Invitations.
- There is no reusable Group, Circle, team, or dashboard entity.
- The Owner cannot transfer ownership or leave while the Shared Habit continues.
- The Owner controls the name, emoji, color, Habit Description, Daily Target, and Streak Goal. Owner changes apply to every Member.
- Categories and overview ordering remain personal to each Member.
- A Shared Habit cannot be archived. A Member leaves instead; the Owner may stop sharing it.

## What is shared

Every Member can see:

- The common Habit definition.
- Each Member's Member Name and Member Color.
- Completion counts by local calendar date.
- Daily and weekly progress derived from those counts.
- Current Streak and Month Total when those metrics apply.

Open Habit never shares Day Notes. It also does not share Categories, ordering, app settings, backups, widget configuration, or unrelated Habits.

This is a cooperative, trusted-small-group feature. The app prevents ordinary mistakes and conflicting edits, but does not claim adversarial tamper resistance. CloudKit read-write participants can technically modify records included in a share; a hostile modified client is outside the threat model.

## Creating a Shared Habit

`Habit Detail → Share Habit` opens setup. The Owner:

1. Chooses and confirms a Member Name.
2. Chooses whether their Shared History includes all existing Habit Days or starts today. `Full History` is the default.
3. Creates the Shared Habit and its first Invitation.

The existing Habit becomes shared in place. Open Habit does not duplicate it. After creation, Open Habit immediately presents the first Invitation with actions to send or copy its link. Habit Detail then shows the Members section and its Invite action for additional people.

Starting fresh affects only what the Owner shares. Their local earlier history remains intact and private.

## Invitations

- Invite creates a single-use CloudKit participant URL for one person.
- An outstanding Invitation reserves one of the ten Member places.
- Invitations do not expire automatically.
- The Invitation screen can copy the URL or open the system share sheet to send it through Messages, AirDrop, or another direct channel.
- The first person to accept the URL becomes a Member immediately; Owner approval is not required.
- Before acceptance, the Owner sees a generic `Pending Invitation`, because no Member Name exists yet.
- The Owner may cancel a pending Invitation or remove a Member who accepted an incorrectly forwarded URL.
- Public and reusable links are not supported.

Single-use participant URLs require iOS 18 or later. Tracking remains available on iOS 17, but creating or accepting a Shared Habit is unavailable there.

## Joining

Acceptance shows an `Opening invitation…` spinner while iCloud loads the Shared Habit, then presents three steps:

1. **Your Name**: enter a Member Name for this Shared Habit. Continue requires a nonblank name of at most 40 characters.
2. **Review Habit**: review the common Habit definition, Owner's Member Name, Member count, and what is shared. Completion counts and derived progress are visible to all Members; Day Notes stay private.
3. **Choose Your Habit**: choose `Start New` (default) to create a new local Habit whose Shared History begins today, or `Use Existing Habit` to select a Private Habit, review the definition differences, and share its full Completion history. The existing-Habit option is unavailable when there are no eligible Private Habits.

Each step shows progress. Continue advances to the next step; native Back navigation preserves the name and tracking choice. Only the final `Join Shared Habit` action completes joining and connects the local Habit. It shows a spinner while joining; a failure keeps the entered choices available for retry.

Connecting an existing Habit is the explicit approval to share its full Completion history. There is no later history visibility toggle. To stop sharing, the Member leaves.

The connected Habit keeps its stable local identifier, creation date, Categories, overview position, Completion history, and Day Notes. Its shared definition fields change to the common definition. Day Notes remain local even when their Habit Day's count is shared.

Rejoining follows the same flow. `Start New` shares nothing from the earlier membership; `Use Existing Habit` shares the selected Habit’s full history, including dates outside the earlier membership.

## Member identity

- A Member Name belongs to one Shared Habit, not to a global Open Habit profile.
- The app may prefill a name from the Apple identity when available, but the Member explicitly confirms it.
- Members may edit their own Member Name and Member Color only.
- The Owner has no power to rename another Member.
- Names need only distinguish this small group; global uniqueness is unnecessary.

Open Habit initially assigns the first available Member Color, alternating between these complementary water and sunrise palettes:

| Index | Hex | Family |
| ---: | --- | --- |
| 0 | `#023E8A` | Water |
| 1 | `#E29578` | Sunrise |
| 2 | `#0077B6` | Water |
| 3 | `#EE6C4D` | Sunrise |
| 4 | `#00B4D8` | Water |
| 5 | `#F95738` | Sunrise |
| 6 | `#34A0A4` | Water |
| 7 | `#FF9F1C` | Sunrise |
| 8 | `#52B69A` | Water |
| 9 | `#F4D35E` | Sunrise |

Member Name and row position remain visible, so color is never the only identifier.

## Presentation

The overview keeps the normal Habit card and adds a small people indicator with the current Member count.

Habit Detail gains a `Members` section. It uses one labeled row per Member at every group size, ordered as:

1. The current Member.
2. The Owner, when different.
3. Remaining Members by join time.

Each row shows Member Color, Member Name, today's or this week's progress, a compact seven-day history, and Current Streak when enabled. Ten Members scroll vertically; the UI does not compress them into an unreadable multi-color calendar.

Tapping another Member opens a read-only version of their shared history using their Member Color. It contains shared metrics and Completion counts, but no edit controls or Day Notes.

There is no separate Sharing tab. Management lives behind the Members section:

- Owners see Invite, pending Invitations, Remove Member, and Stop Sharing.
- Other Members see Leave Shared Habit.

The first version has no leaderboard, group score, podium, competition mode, feed, events, chat, comments, reactions, or Completion notifications.

## Leaving, removal, and stopping sharing

When a Member leaves or the Owner removes them:

- Shared visibility ends.
- Their local Habit and all personal history remain in place as a Private Habit.
- The Habit keeps the latest common definition; Open Habit does not restore an earlier definition.
- Other Members stop seeing that Member after synchronization.

The Owner cannot leave. `Stop Sharing` requires an explicit confirmation and then:

- Ends the CloudKit share.
- Removes shared visibility for everyone.
- Preserves the Owner's Habit and personal history locally as a Private Habit.
- Preserves every other Member's Habit and history locally as a Private Habit after their next synchronization.

If the Owner later wants to delete the Habit, they use the ordinary `Delete Habit` action in Habit Settings after sharing has stopped.

There is no ownership migration. A former Member may create a new Shared Habit and invite the others again.

`Delete All Data` first requires an Owner to stop sharing every Shared Habit they own. A non-owner leaves Shared Habits before their now-private data is deleted.

## Time and derived progress

Every Completion retains the recording Member's local `YYYY-MM-DD` calendar date. The Shared Habit stores one common first day of week, copied from the Owner's effective setting when sharing begins. All Members use that boundary for shared weekly progress and Weekly Streaks.

This is a sane deterministic default, not an attempt to reconcile every travel or time-zone edge case in the first version.

## Synchronization and offline behavior

- Personal tracking always commits to the existing local journal first.
- Only the common definition, Member identity, and Completion counts are projected into CloudKit shared records.
- Day Notes never enter the shared projection.
- Synchronization runs after relevant edits, when the app or Shared Habit opens, on manual refresh, and opportunistically in the background.
- The product promises eventual synchronization, not instant or hourly delivery.
- Cached Member data remains visible offline with an `Updated …` indication when useful.
- A Member may correct their own past counts. The shared view changes after synchronization; there is no audit feed.
- If a share ended while a Member was offline, the next synchronization converts the local Habit to Private without removing personal history.

The small-group limit and one compact progress projection per Member keep the record and request count deliberately low.

## Widgets, Shortcuts, and backups

- Widgets and App Intents operate only on the current Member's local progress.
- Other Members' data appears only inside the app initially.
- A native backup contains the common Habit definition plus only the exporting person's identity, Habit Days, and private Day Notes. It never contains another Member's data.
- Restoring without the live CloudKit share produces a Private Habit.

## Acceptance criteria for the first complete release

- An Owner can share an existing Habit, choose full history or a fresh start, and send a single-use Invitation.
- A second iCloud account can accept, choose Start New or Use Existing Habit, and appear as a Member without Owner approval.
- Both Members can record offline and later see the other's Completion counts after synchronization.
- Neither Member can see the other's Day Notes.
- Owner definition changes converge for every Member; non-owners have no definition controls.
- Member Name, Member Color, ordering, the ten-person cap, and pending Invitation reservations behave as specified.
- Leaving, removal, and stopping sharing preserve each person's local Habit and personal history.
- Existing private Habit sync, widgets, App Intents, import, backup, and restore continue to work.
