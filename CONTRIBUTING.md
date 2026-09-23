# Contributing to Open Habit

Thank you for helping improve Open Habit. Bug reports, focused code changes, documentation, and translations are welcome.

## Before opening a change

Search the existing [issues](https://github.com/zamai/open-habit/issues). For a substantial feature or behavior change, open an issue first so the scope and product fit can be agreed before implementation.

Do not include personal habit data, Apple credentials, signing files, provisioning profiles, or screenshots containing private information. Report security concerns privately according to [SECURITY.md](SECURITY.md).

## Build and test

Open `OpenHabit.xcodeproj` with Xcode 26 or newer. The app targets iOS and iPadOS 17 or later. The checked-in project is generated from `project.yml` with XcodeGen.

Run the domain suite with:

```sh
swift test --package-path OpenHabitCore
```

Run the app and UI test selection used by CI with:

```sh
bash scripts/ci/test.sh
```

Signed-device, iCloud, and TestFlight checks require maintainer-managed Apple configuration. They are not expected for ordinary contributions.

## Pull requests

Keep changes small and coherent. Describe the observable behavior, the reason for the change, and what you verified. Add or update tests when they protect meaningful behavior or risk.

By contributing, you agree that your contribution is licensed under the repository's [MIT license](LICENSE).
