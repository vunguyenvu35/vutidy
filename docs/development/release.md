# Releasing Vutidy

Vutidy is released by the **release** GitHub Actions workflow ([`.github/workflows/release.yml`](../../.github/workflows/release.yml)). It builds one universal macOS app (Apple silicon and Intel), packages it as a disk image and a zip, writes the checksums and publishes everything as a GitHub Release.

## Contents

- [How to release](#how-to-release)
- [What the workflow does](#what-the-workflow-does)
- [Files of a release](#files-of-a-release)
- [Signing and notarization](#signing-and-notarization)
- [Building a release by hand](#building-a-release-by-hand)
- [The ci workflow](#the-ci-workflow)
- [How the app updates itself](#how-the-app-updates-itself)
- [Limits](#limits)

## How to release

1. Write the notes of the new version in [`RELEASE_NOTES.md`](../../RELEASE_NOTES.md) as a section that starts with `# Vutidy <version>` (the line must match exactly). The workflow publishes that section as the body of the release.
2. Change [`VERSION`](../../VERSION) to the new version (`0.2.0`, no leading `v`).
3. Merge that change into `main`.

That is all. The workflow notices the change of `VERSION`, builds, and publishes (the tag `v<version>` is created together with the release, only after the build succeeded). If the tag already exists, nothing is published (the version was already released), so an unrelated merge never makes a second release.

Other ways to start it:

| Start | What happens |
| --- | --- |
| Push a tag `v<version>` | Builds and publishes. The tag **must** equal `v` + the content of `VERSION`, otherwise the run stops with an error (the files would carry the wrong version). |
| *Actions → release → Run workflow* | Builds only and attaches the files to the run as an artifact. Nothing is published. Use it to try the packaging. |

Versions below `1.0.0` are marked as **pre-releases** on GitHub.

## What the workflow does

Three jobs:

| Job | Does |
| --- | --- |
| `prepare` | Decides the tag and whether to publish. For a push to `main` it checks whether the tag already exists (the tag itself is created later, with the release). |
| `build` | On a macOS runner: `swift test`, imports the signing certificate if the secrets exist, builds the **universal** app with `scripts/make-app.sh`, notarizes it if the secrets exist, packages it with `scripts/package-macos.sh`, and uploads the files as an artifact. |
| `release` | Downloads the artifact, adds a copy of each file **without the version in its name**, writes `SHA256SUMS`, and creates the GitHub Release (or adds the files to a release that was made by hand for the same tag). |

## Files of a release

| File | Use |
| --- | --- |
| `vutidy-<version>-macos.dmg` | The installer: drag **Vutidy** onto *Applications*. It also holds `THIRD_PARTY_NOTICES.md`. |
| `vutidy-<version>-macos.zip` | The same app as a zip, made with `ditto` so that the signature stays intact. |
| `vutidy-macos.dmg`, `vutidy-macos.zip` | Copies without the version, so that this link is always the newest release: `https://github.com/vunguyenvu35/vutidy/releases/latest/download/vutidy-macos.dmg` |
| `SHA256SUMS` | The SHA-256 of every file above. Check a download with `shasum -a 256 -c SHA256SUMS --ignore-missing`. |

## Signing and notarization

Without any secret the app is signed **ad-hoc**. It works, but macOS shows the "cannot verify the developer" warning the first time, and the user has to use *Open Anyway* (see [Installing on macOS](../getting-started/install-macos.md)).

To avoid that you need an Apple Developer ID. Add these **repository secrets** (*Settings → Secrets and variables → Actions*):

| Secret | Value | Needed for |
| --- | --- | --- |
| `MACOS_CERTIFICATE` | The *Developer ID Application* certificate exported from Keychain Access as `.p12`, encoded with `base64 -i certificate.p12 \| pbcopy` | Signing |
| `MACOS_CERTIFICATE_PASSWORD` | The password you chose when exporting the `.p12` | Signing |
| `MACOS_SIGN_IDENTITY` | The identity name, for example `Developer ID Application: Your Name (TEAMID)` (`security find-identity -v -p codesigning` lists it) | Signing |
| `APPLE_ID` | The Apple ID e-mail of the developer account | Notarization |
| `APPLE_TEAM_ID` | The 10-character team ID | Notarization |
| `APPLE_APP_PASSWORD` | An *app-specific password* made at appleid.apple.com (not the account password) | Notarization |

- With the three **signing** secrets the app is signed with the hardened runtime and a timestamp.
- With the signing secrets **and** the three **notarization** secrets the app is also notarized and the ticket is stapled, so it opens without any warning, even offline.

Each step checks whether its secrets exist and is skipped when they do not, so you can add them one group at a time. Never commit a certificate or a password.

A fixed certificate has a second benefit: macOS keeps **Full Disk Access** across updates only for an app that is signed with the same identity every time. An ad-hoc build is a new identity on every build, so the permission has to be granted again after each update.

## Building a release by hand

```sh
ARCHS=universal scripts/package-macos.sh --build    # dist/vutidy-<version>-macos.{dmg,zip,sha256}
```

| Variable | Meaning |
| --- | --- |
| `ARCHS=universal` | Build for Apple silicon and Intel. Leave it out to build for the machine you are on (faster). |
| `CODESIGN_IDENTITY` | A signing identity from your keychain. Default: ad-hoc. |
| `DIST_DIR` | Where the files go. Default: `dist`. |
| `BUILD_NUMBER` | The build number in `Info.plist`. Default: the workflow run number, or `1`. |

To publish files built by hand, create the release with `gh release create v<version> dist/vutidy-*` and let the workflow run for that tag: it adds the files that are missing.

## The ci workflow

[`ci.yml`](../../.github/workflows/ci.yml) runs on every push to `main` and on every pull request:

- **test**: `swift build` and `swift test`.
- **docs**: `scripts/check-doc-links.sh` (links and images that no longer point anywhere).
- **package**: the same universal build and packaging as a release, so a broken packaging step shows up in a pull request and not on release day. The result is kept as an artifact for seven days.

A newer push to the same branch cancels a run that is still going.

## How the app updates itself

The in-app updater ([user guide](../user-guide/16-updating-vutidy.md)) reads `https://api.github.com/repos/vunguyenvu35/vutidy/releases` and needs from each release:

- a zip named `vutidy-<version>-macos.zip` (the workflow already makes it; the unversioned copy is ignored);
- a `SHA256SUMS` asset that lists that zip. **A release without it cannot be installed by the app.**
- the app inside must have the same bundle ID and version as the tag, and a valid signature (the same Team ID when the installed app has one).

GitHub marks every version below `1.0.0` as a pre-release, so the updater lists all releases instead of using `/releases/latest`. A draft is never offered.

To try the whole flow without publishing, point it at a local JSON file shaped like the GitHub response: `VUTIDY_UPDATE_FEED=file:///path/releases.json` (add `VUTIDY_UPDATE_AUTOINSTALL=1` to install straight away). The asset URLs may be `file://` too.

## Limits

- The workflow could not be run from the machine where it was written. Its YAML is valid and the packaging scripts were run locally, but the first real run on GitHub may still need a fix. Try it with *Run workflow* before relying on it.
- There is **no self-update** in the app yet: users install a new version from the release page.
- The signing and notarization steps are untested until the secrets exist.
- The universal build needs a recent Xcode on the runner (`macos-latest` has one).
