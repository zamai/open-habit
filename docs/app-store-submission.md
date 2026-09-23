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
- Privacy policy source: [`privacy-policy.md`](privacy-policy.md)
- Marketing website: <https://getopenhabit.com/>
- Public privacy policy: <https://getopenhabit.com/privacy>
- Public support: <https://getopenhabit.com/support>
- Contact email: `contact@getopenhabit.com`
- Source code: <https://github.com/zamai/open-habit>

## App Review notes

Open Habit requires no sign-in and has no purchases. All personal tracking works offline. iCloud enables private synchronization and Shared Habits when the device is signed in to an Apple Account.

Shared Habits use private CloudKit Invitations between people who know each other. To exercise the full invitation flow, use two devices signed in to different Apple Accounts on iOS 18 or later. Create a Habit, open its detail, choose Share Habit, create an Invitation, and accept it on the other device. Day Notes and categories remain private.

Settings contains JSON export and import, recovery backups, iCloud status, and Delete All Data. Home Screen widgets are configured through the system widget editor. Shortcuts exposes Add Completions, Remove Completions, Today’s Progress, and Set Day Note.

## Release gates

- [x] No third-party SDKs, analytics, advertising, accounts, or purchases.
- [x] Privacy manifest declares the file-timestamp API used to display local recovery-backup dates.
- [x] Encryption exemption is declared; the app only uses Apple platform encryption.
- [x] App and widget identifiers, App Group, CloudKit container, Push Notifications, and Production CloudKit schema are configured.
- [x] Release checks pass: 40 core tests (with 3 expected private-fixture skips), 7 app integration/widget tests, and the UI automation suite, including deletion confirmation and Shared Habit joining.
- [x] Make the source repository public before publishing copy that describes Open Habit as open source.
- [x] Publish and verify the marketing, privacy, and support pages at the `getopenhabit.com` URLs above.
- [x] Add the `getopenhabit.com` marketing, privacy, and support URLs to App Store Connect.
- [x] Route `contact@getopenhabit.com` to the verified private inbox and use it for production and TestFlight review contacts.
- [x] Add Privacy Policy, Support, and Source Code links in Settings.
- [x] Complete the age-rating questionnaire: 9+ in 172 countries or regions, 12+ in Vietnam, with regional ratings shown separately; operating systems earlier than version 26 retain a global 4+ rating with regional exceptions.
- [x] Declare that Open Habit is **not** a regulated medical device in any country or region.
- [x] Configure the app as free and available in all 175 current territories, including new territories automatically.
- [x] Set Health & Fitness as the primary category and Productivity as the secondary category.
- [x] Generate and upload current 6.9-inch iPhone and 13-inch iPad screenshots from [`app-store-assets`](app-store-assets).
- [x] Upload build 38, verify it is assigned to both TestFlight groups and in external beta testing, and select it for App Store version 1.0.
- [x] Complete App Review contact details and save the prepared review notes.
- [x] Declare the individual seller as a **non-trader** for EU Digital Services Act compliance.
- [x] Complete and publish the App Privacy questionnaire as **Data Not Collected**.
- [x] Submit version 1.0 with build 38 for App Review on September 23, 2026; release automatically after approval.
- [ ] Complete the signed-device checks in [`verification.md`](verification.md), especially two-account Shared Habit synchronization and a terminated-app widget action.
