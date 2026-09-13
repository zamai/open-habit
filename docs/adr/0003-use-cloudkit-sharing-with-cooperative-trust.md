# Use CloudKit Sharing with cooperative trust

Shared Habits use CloudKit Sharing rather than an Open Habit account, API, or hosted synchronization service. Each Shared Habit is one private CloudKit record hierarchy containing its common definition, Member identities, and a compact Completion-count projection for each Member. Personal journals and Day Notes remain in each person's private database and local storage.

Shared records reuse the already-deployed `HabitEdit` record type and its `payload` asset field. Stable record-name prefixes distinguish the hierarchy root, Member identity, progress, and private membership cache. This keeps the production schema unchanged while the decoded payload types remain explicit in Open Habit Core.

This preserves Open Habit's local-first behavior and avoids operating a server, but it is not peer-to-peer: synchronization and Invitations depend on Apple's iCloud infrastructure and iCloud accounts. It also keeps the feature Apple-only in the first version; Android has no native CloudKit SDK.

CloudKit's read-write permission applies to the shared hierarchy rather than to individual Member-owned records. The Open Habit UI therefore allows a Member to edit only their own progress, while accepting that a deliberately modified client could tamper with another record. Small invited groups are treated as cooperative. Strong authorization, audit history, public sharing, competitive groups, and hostile-client resistance would require an application backend and are deliberately outside this design.

Only Completion counts are copied into the shared hierarchy. Day Notes never enter it. This separate projection is required even though reusing the existing private journal payload would be mechanically simpler, because sharing that payload would disclose notes, categories, settings, and unrelated private data.
