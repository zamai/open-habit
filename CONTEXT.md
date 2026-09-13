# Open Habit

This context describes personal habits and the daily record a person builds by practising them.

## Language

**Habit**:
A positive behaviour a person intends to practise regularly. A Habit has a name, emoji, color, one-sentence Habit Description, Daily Target, and optional Streak Goal, and remains active until it is archived or deleted.
_Avoid_: Goal, task, avoidance habit

**Habit Description**:
A one-sentence explanation of a Habit.
_Avoid_: Instructions, long description

**Completion**:
One recorded occurrence of performing a Habit. A Habit may have multiple Completions on the same day, but quick logging stops when the Daily Target is reached.
_Avoid_: Check-in, tick

**Daily Target**:
The current Habit-level threshold used to interpret every Habit Day and cap new Completions. Changing it re-evaluates all past and present Habit Days.
_Avoid_: Historical target, streak goal

**Daily Progress**:
The comparison between a Habit Day's Completion count and the Habit’s current Daily Target: empty, in progress, or complete. It is derived from those values rather than recorded independently; there is no separate overachievement or failure state.
_Avoid_: Stored status, failed day

**Streak Goal**:
An optional rule for deriving a Current Streak. A Daily Streak Goal requires one completed Habit Day per day. A Weekly Streak Goal requires a chosen number of completed Habit Days, from one through seven, in each calendar week.
_Avoid_: Stored streak, Completion Target

**Current Streak**:
The number of consecutive days or weeks that satisfy a Habit's Streak Goal. It is derived from Habit Days using the current Daily Target and Streak Goal. An unfinished current day or week does not break it.
_Avoid_: Saved streak count

**Month Total**:
The sum of all Completions for a Habit in the calendar month currently visible in Habit Detail.
_Avoid_: Completed days, monthly streak

**Habit Day**:
One Habit on one local calendar date, including its Completion count and optional Day Note. Its date is fixed when recorded, and an empty Habit Day means only that no Completions were recorded.
_Avoid_: Entry, log

**Day Note**:
Optional plain-text commentary attached to one Habit Day. There is at most one Day Note per Habit Day, and it may contain up to 500 characters across multiple lines.
_Avoid_: Habit note, journal entry

**Archived Habit**:
A Habit preserved with its history but excluded from current tracking views and widgets. Dates while it is archived remain ordinary empty Habit Days.
_Avoid_: Deleted habit, inactive habit

**Category**:
A named grouping of Habits. A Habit may belong to multiple Categories, and a Category may have no Habits.
_Avoid_: Habit, schedule
