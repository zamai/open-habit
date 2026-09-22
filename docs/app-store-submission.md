# App Store submission

## Product metadata

- Name: **Open Habit: Daily Tracker**
- Subtitle: **Private habits. Small steps.**
- Version: **1.0**
- Primary locale: **English (U.S.)**
- Copyright: **2026 Oleksandr Zamai**
- Keywords: `habit tracker,streaks,widgets,routines,goals,journal,shortcuts,offline,private,icloud`
- Promotional text: **Build habits with interactive widgets, private iCloud sync, Shortcuts, Day Notes, and portable JSON backups.**
- Description: [`store-description.txt`](store-description.txt)
- Privacy policy: [`privacy-policy.md`](privacy-policy.md)

## App Review notes

Open Habit requires no sign-in and has no purchases. All personal tracking works offline. iCloud enables private synchronization and Shared Habits when the device is signed in to an Apple Account.

Shared Habits use private CloudKit Invitations between people who know each other. To exercise the full invitation flow, use two devices signed in to different Apple Accounts on iOS 18 or later. Create a Habit, open its detail, choose Share Habit, create an Invitation, and accept it on the other device. Day Notes and categories remain private.

Settings contains JSON export and import, recovery backups, iCloud status, and Delete All Data. Home Screen widgets are configured through the system widget editor. Shortcuts exposes Add Completions, Remove Completions, Today’s Progress, and Set Day Note.

## Release gates

- [x] No third-party SDKs, analytics, advertising, accounts, or purchases.
- [x] Privacy manifest declares the file-timestamp API used to display local recovery-backup dates.
- [x] Encryption exemption is declared; the app only uses Apple platform encryption.
- [x] App and widget identifiers, App Group, CloudKit container, Push Notifications, and Production CloudKit schema are configured.
- [x] Release analyzer, core tests, app integration tests, widget rendering, deletion UI, Shared Habit join UI, and Files import/export/restore tests pass.
- [x] App Store copy no longer promises public source access while the repository is private.
- [ ] Publish the privacy policy and provide its public URL.
- [ ] Provide a public support URL and support contact details.
- [ ] Complete the age-rating questionnaire, pricing, and availability in App Store Connect.
- [x] Generate current 6.9-inch iPhone and 13-inch iPad screenshots in [`app-store-assets`](app-store-assets).
- [ ] Upload the screenshots to App Store Connect.
- [ ] Upload and select the final release build after device acceptance.
- [ ] Complete the signed-device checks in [`verification.md`](verification.md), especially two-account Shared Habit synchronization and a terminated-app widget action.
