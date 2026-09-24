# Open Habit marketing website content plan

Historical planning draft from September 2026. The current website source and published copy live in [`site/`](../../site/); this document is retained for the reasoning behind that first design. Its open decisions and asset list are not a current launch checklist.

## Purpose

Create a small, trustworthy informational website that helps a visitor quickly answer:

1. What is Open Habit?
2. Why should I choose it over another habit tracker?
3. How does it handle my data?
4. What can it do?
5. Where can I download it or inspect the source?

The page should make the product feel simple. It should not reproduce the complete product specification or read like a checklist of implementation details.

Canonical public pages:

- Marketing site: <https://getopenhabit.com/>
- Support: <https://getopenhabit.com/support>
- Privacy: <https://getopenhabit.com/privacy>
- Contact: <contact@getopenhabit.com>

## Audience

Primary audience:

- iPhone and iPad users who want a focused habit tracker without subscriptions, ads, or another account.
- People who value fast tracking from widgets and Shortcuts.
- Privacy-conscious users who want their data to remain under their control.

Secondary audience:

- Open-source users who want to inspect, build, or contribute to the app.
- HabitKit users looking for a path to import their existing data.
- Small groups who want to practise a habit together without joining a social network.

## Positioning

### Product category

A private, offline-first habit tracker for iPhone and iPad.

### Core promise

Record the small things you do every day with almost no friction, while keeping ownership of your data.

### Three message pillars

1. **Fast to use** — record progress in the app, from interactive Home Screen widgets, or with Shortcuts.
2. **Private by design** — no Open Habit account, advertising, analytics, or developer-operated user-data service. Tracking works offline and syncs through the user's private iCloud database.
3. **Yours to keep** — free, open source, exportable, restorable, and not locked behind a subscription.

### Important wording

Use:

- “No Open Habit account required.”
- “Your data is stored on your devices and synced through your private iCloud database.”
- “The developer does not collect your habit data.”
- “Free, with no ads or in-app purchases.”
- “Open source under the MIT license.”

Avoid:

- “No account required” without qualification. iCloud sync and Shared Habits require an Apple Account.
- “Stored in iCloud only.” Local storage is the immediate source and offline tracking is a core feature.
- “We collect no user data” as a broad statement. Shared Habit data is processed by Apple through CloudKit, and support information may be sent voluntarily.
- “iCloud backup.” iCloud provides synchronization and reinstall recovery, not a versioned backup against edits or deletions.
- “Real-time sharing.” Shared Habit progress synchronizes eventually and continues working offline.

## Recommended page structure

### 1. Header

Keep navigation short:

- Features
- Privacy
- Open Source
- FAQ
- GitHub

Persistent actions:

- Primary: Download on the App Store
- Secondary: View on GitHub

Links:

- GitHub: <https://github.com/zamai/open-habit>
- App Store: <https://apps.apple.com/app/id6808947599> (becomes the primary destination when the listing is live).

### 2. Hero

The hero should explain the product and its difference without requiring the visitor to scroll.

Working direction:

- Eyebrow: “Free and open source for iPhone and iPad”
- Headline: “A little, every day.”
- Supporting sentence: “A private habit tracker built for quick check-ins from your Home Screen, Shortcuts, or the app.”
- Primary action: “Download on the App Store”
- Secondary action: “View the source”
- Product proof: a strong iPhone overview image paired with a Home Screen widget image or short interaction recording.

Short trust row below the actions:

- No subscription
- No ads or analytics
- No Open Habit account
- Works offline

Do not place every feature in the hero. The first screen should sell the product promise, not the specification.

### 3. Signature interaction: track without opening the app

Lead the feature story with the clearest product differentiator: interactive widgets.

Content to show:

- Add a Completion directly from the Home Screen.
- See recent history at a glance.
- Choose widgets for one, three, or six Habits.
- Progress is saved locally first, so the interaction does not depend on a network connection.

Best media:

- A short, silent recording of tapping a widget and seeing progress update.
- A clean Home Screen capture with correctly configured emoji and Habit names.

### 4. Flexible tracking

Explain the core product model in user language:

- Create Habits with an emoji, name, description, color, and Daily Target.
- Use a simple check for a once-a-day Habit or build toward a larger target.
- Set an optional daily or weekly Streak Goal.
- Reorder, archive, restore, or permanently delete Habits.
- Correct today or any past day when reality does not match the initial check-in.

Avoid turning this into a long settings inventory. One image of the overview and one focused image of Habit creation should be enough.

### 5. History with context

Show that Open Habit is useful after the check-in:

- Rolling year history for long-term patterns.
- Month calendar for precise daily review and correction.
- Current Streak and monthly Completion total.
- Optional private Day Notes for context.
- Empty days are left empty; the app does not shame the user with “failed” or “overdue” labels.

The last point is a valuable expression of the product philosophy and may deserve more prominence than another statistics bullet.

### 6. Shortcuts and automation

Present this as power without complexity:

- Add Completions.
- Remove Completions.
- Get progress for a Habit and date.
- Set a Day Note.
- Combine Open Habit actions with other apps in Apple's Shortcuts app.

Use one concrete example instead of only listing actions, such as adding a reading Completion from an existing bedtime Shortcut.

### 7. Private by design

This section should be direct and specific rather than using generic privacy language.

Suggested content:

- All tracking works offline.
- Data lives on the user's devices and, when available, in their private iCloud database.
- There is no Open Habit account or developer-operated synchronization server.
- There are no ads, analytics, or tracking SDKs.
- The developer does not receive Habit data through the app.
- iCloud changes, including deletions, synchronize between devices; exported files are the user-controlled backup.

Link to the full privacy policy: <https://getopenhabit.com/privacy>

A small diagram may help later: `iPhone ↔ private iCloud ↔ iPad`, with no Open Habit server in the path.

### 8. Shared Habits, without the social network

Treat Shared Habits as a substantial feature, but keep it below the individual tracking and privacy story so visitors first understand the core app.

Content to show:

- Invite up to nine other people to practise the same Habit.
- Each Member records only their own progress.
- Members can see one another's Completion counts and progress.
- Day Notes, categories, ordering, settings, widgets, and unrelated Habits stay private.
- Invitations are private and single-use.
- Leaving or stopping sharing preserves each person's own Habit and history.

Qualification:

- Creating or accepting Shared Habit invitations requires iOS 18 or later and an Apple Account with iCloud available.

Use cooperative language such as “keep each other going.” Avoid leaderboards, competition, feeds, or claims of live synchronization; those are intentionally not part of the product.

### 9. Your data stays portable

This section supports both trust and practical utility:

- Export a complete Open Habit JSON backup.
- Restore a backup later.
- Import supported HabitKit version 2 exports.
- Local recovery backups are created before replacement, import, and deletion.
- Delete all app data from Settings.

Keep JSON format details on GitHub documentation rather than the marketing page. Link to the data format documentation for technical visitors.

### 10. Free and open source

Make this a first-class reason to trust the product, not a small footer badge.

Suggested content:

- Free to download and use.
- No ads, in-app purchases, or subscription.
- Source available under the MIT license.
- Contributions, ideas, bug reports, documentation, and translations are welcome.

Actions:

- View on GitHub: <https://github.com/zamai/open-habit>
- Read the license: <https://github.com/zamai/open-habit/blob/main/LICENSE>
- Report an issue: <https://github.com/zamai/open-habit/issues>

Only publish the source and contribution claims after the repository is public.

### 11. FAQ

Recommended launch questions:

1. Is Open Habit really free?
2. Does Open Habit require an account?
3. Where is my data stored?
4. Does tracking work without an internet connection?
5. Does Open Habit collect analytics or show ads?
6. Is iCloud sync a backup?
7. Can I move my data to another app or keep my own backup?
8. Can I import my HabitKit data?
9. What do other people see in a Shared Habit?
10. Which devices and operating-system versions are supported?
11. Is there an Android, Apple Watch, Mac, or web version?
12. How can I contribute or report a problem?

Answers should be short and candid. For unsupported platforms, say that version 1.0 is for iPhone and iPad rather than publishing speculative roadmap promises.

### 12. Final call to action and footer

Repeat the simple promise and the two main actions:

- Download on the App Store
- View on GitHub

Footer links:

- Features
- Privacy Policy: <https://getopenhabit.com/privacy>
- Support: <https://getopenhabit.com/support>
- GitHub
- Issues
- License
- App Store

Add copyright and a brief statement that iCloud, iPhone, iPad, App Store, and Shortcuts are Apple trademarks where legally appropriate.

### Required supporting pages

The Support page at <https://getopenhabit.com/support> should:

- identify Open Habit as a free, non-commercial, open-source project;
- provide the public contact address <contact@getopenhabit.com> and GitHub Issues for reproducible public bug reports;
- link to the GitHub repository, privacy policy, and App Store listing;
- never publish the maintainer's home address or other private contact details.

The Privacy page at <https://getopenhabit.com/privacy> should faithfully render the policy maintained in [`privacy-policy.md`](../privacy-policy.md). The website copy must not broaden or contradict that policy.

## Feature inventory and priority

### Lead with these

- Interactive one-, three-, and six-Habit Home Screen widgets.
- Shortcuts support.
- Offline-first tracking with private iCloud sync.
- No Open Habit account, ads, analytics, subscription, or in-app purchases.
- Rolling history, calendar review, daily/weekly Streak Goals, and Day Notes.
- Free and open source.

### Give a dedicated supporting section

- Shared Habits for small invited groups.
- JSON export, restore, recovery backups, and HabitKit import.

### Mention within another section or FAQ

- iPhone and iPad adaptive layouts.
- Light, Dark, and System appearance.
- Manual ordering, archiving, and deletion.
- Custom emoji and colors.
- Local calendar dates and editable past progress.
- iOS 17 minimum; iOS 18 minimum for Shared Habit invitations.

### Do not market as a current feature

- Category filtering or editing. Categories are preserved during import and export, but their management UI is not available yet.
- Apple Watch, macOS, Android, web, reminders, Lock Screen widgets, or Health integration.
- Real-time collaboration, leaderboards, social feeds, comments, or reactions.
- Versioned cloud backup.

## Content and media

The planning-stage media set included clean iPhone light and dark captures, iPad captures, one-, three-, and six-Habit widget renders, and a looping Completion interaction in MP4, WebM, and GIF formats. Selected media for the published website is in [`site/assets`](../../site/assets/). The captures use the app's built-in Exercise, Drink water, and Read five pages examples.

Remaining launch assets:

1. App icon in SVG or high-resolution PNG.
2. Shortcuts action capture or small automation example.
3. Shared Habit Members capture using fictional names and safe sample data.
4. Open Graph/social sharing image.

Use the MP4 or WebM interaction loop on the website and keep the GIF as a fallback. Avoid screenshots with question-mark placeholder icons, test-only names, developer apps, or other distracting Home Screen content.

## Content decisions to make before final copy

The launch target is confirmed as the public App Store release. The primary call to action is therefore **Download on the App Store**; TestFlight and waitlist language should not appear on the public site.

Remaining decisions:

1. **Open-source timing:** Will the GitHub repository be public when the site launches? If not, keep the URL ready but do not advertise source access prematurely.
2. **Primary emphasis:** Use widgets and frictionless tracking as the acquisition message; use privacy and ownership as the reason to trust and stay.
3. **Shared Habits prominence:** Recommended: a dedicated mid-page section, not part of the hero, until two-account device verification is complete.
4. **Project voice:** Recommended: calm, plain, encouraging, and non-judgmental. Avoid productivity pressure, streak anxiety, and exaggerated privacy claims.
5. **Project attribution:** Use “Open Habit” rather than personal maintainer details in public website copy.
6. **Sustainability:** Decide whether to mention donations or sponsorship. Do not add this unless there is an actual funding channel and a clear reason for it.

## Suggested first-release scope

Keep version one of the website to a single page plus the existing Privacy and Support pages. The single page should contain:

1. Header
2. Hero
3. Interactive widgets
4. Tracking, history, and Shortcuts
5. Privacy and iCloud
6. Shared Habits
7. Data portability
8. Free and open source
9. FAQ
10. Final call to action and footer

Defer a blog, changelog, roadmap, comparison table, press kit, and separate feature pages until there is evidence that visitors need them. GitHub Releases can serve as the early changelog, and GitHub Issues can serve as the public feedback channel.

## Success criteria for the content

A visitor should understand within a few seconds that Open Habit is:

- a habit tracker for iPhone and iPad;
- fast to use from widgets and Shortcuts;
- private, offline-first, and synchronized through iCloud without an Open Habit account;
- free, without ads or purchases;
- open source and able to export its data.

After reading the whole page, the visitor should also understand Shared Habits, backups and import, platform requirements, and exactly where to download the app or view the source.
