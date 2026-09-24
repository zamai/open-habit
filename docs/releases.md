# Releases

Open Habit keeps merging and distribution separate:

- Pull requests and every push to `main` run the deterministic app tests. A `main` push does not publish a build.
- A manual run of the **iOS** workflow on `main` publishes the current commit to every configured TestFlight group. Select the `maintainer-mac` runner only when that machine should build it; the default uses GitHub's runner.
- A release-candidate tag such as `v1.1-rc.1` or `v1.1.0-rc.1` runs the tests, publishes a new TestFlight build to every configured group, submits it for Beta App Review when required, and creates a GitHub prerelease.
- A stable tag such as `v1.1` or `v1.1.0` runs the tests, publishes a new build, attaches that exact build to the matching App Store version, submits it for App Review, and creates a GitHub release.

The numeric tag version must match `MARKETING_VERSION` in `project.yml`; the optional `.0` patch component is accepted. RC numbers start at 1.

## Stable-release preparation

Before pushing a stable tag:

1. Finish testing an RC from the same commit.
2. Prepare the matching App Store version and its metadata in App Store Connect.
3. Confirm the App Store version's release mode. The workflow preserves the configured choice between automatic release after approval and manual release.
4. Create the stable tag on the tested commit and push it.

For example:

```sh
git tag -a v1.1-rc.1 -m 'Open Habit 1.1 RC 1'
git push origin v1.1-rc.1

# After RC verification and App Store metadata preparation:
git tag -a v1.1 -m 'Open Habit 1.1'
git push origin v1.1
```

Tags are the deliberate distribution triggers. Do not reuse or move a published release tag; make a new RC number or patch release instead.
