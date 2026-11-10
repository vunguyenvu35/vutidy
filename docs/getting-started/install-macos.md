# Installing on macOS

Vutidy is built from source with Swift Package Manager. There is no notarized download yet, so you either run it from the terminal or build a small `.app` and open that once.

## Contents

- [What you need](#what-you-need)
- [Run it from the terminal](#run-it-from-the-terminal)
- [Build Vutidy.app](#build-vutidyapp)
- [Open an app that is not notarized](#open-an-app-that-is-not-notarized)
- [Grant Full Disk Access](#grant-full-disk-access)
- [Remove Vutidy](#remove-vutidy)

## What you need

- macOS 13 (Ventura) or later, Apple Silicon or Intel.
- Xcode **or** the Command Line Tools (`xcode-select --install`) with Swift 5.9 or later.

## Run it from the terminal

```bash
git clone <this repository> && cd vutidy
swift build
swift run Vutidy
```

This runs the app as a bare executable. It works for trying things out, but it has no bundle ID and no icon, so macOS lists it as a nameless program and it **cannot be added to Full Disk Access** in a useful way. Use the `.app` below for real use.

## Build Vutidy.app

```bash
scripts/make-app.sh
open dist/Vutidy.app
```

The script builds a release binary, puts it in `dist/Vutidy.app` with the icon (`docs/assets/brand/AppIcon.icns`) and an `Info.plist` (bundle ID `com.vutidy.app`, minimum macOS 13) and signs it **ad hoc** (`codesign --sign -`). Move it to `/Applications` if you like.

An ad-hoc signature changes with every build, so macOS treats each rebuild as a new app and may ask you to grant Full Disk Access again. Signing with a Developer ID certificate avoids that (see [Development](../development/development.md#packaging)).

## Open an app that is not notarized

The first time you open `Vutidy.app`, Gatekeeper may say *"Vutidy" can't be opened because Apple cannot check it for malicious software.* Nothing is wrong with the build; Apple has simply not seen it.

1. Open **Vutidy** from Finder. macOS blocks it; click **Done**.
2. Open **System Settings → Privacy & Security** and scroll to **Security**.
3. Next to *"Vutidy" was blocked…* click **Open Anyway** and confirm with your password or Touch ID.
4. Open Vutidy again and choose **Open**.

A build you made yourself is not quarantined by macOS, so this step is usually not needed for `dist/Vutidy.app`.

## Grant Full Disk Access

Mail attachments, the Photos cache and the Safari cache live in folders macOS protects. Without **Full Disk Access** Vutidy still works but cannot scan those. A banner at the top of the relevant pages says so and can be dismissed.

The quick way: press **Grant access…** in the banner (or in *Settings → Protection*). Vutidy opens System Settings and shows a guide panel with the app icon to drag into the list; it notices when the permission is on. If the permission is stuck, **Reset permission** clears it first. The manual steps are below.

1. Run `dist/Vutidy.app` (not `swift run`).
2. Open *System Settings → Privacy & Security → Full Disk Access* (**Grant access…** opens it for you).
3. Click **+**, choose `Vutidy.app` (or drag the icon from the guide panel into the list; *Finder → right-click Vutidy → Show in Finder* if you need the file), and switch it on.
4. Quit and reopen Vutidy. *Settings → Protection* shows **Granted** when it works; **Check again** re-reads it.

If Vutidy's name or icon is missing from the list, you started it with `swift run`. See [Troubleshooting](../user-guide/15-troubleshooting.md#vutidy-is-missing-from-full-disk-access).

## Remove Vutidy

Delete `Vutidy.app`. Its data is in `~/Library/Application Support/Vutidy` (the Quarantine, the audit log, your own rules and the speed-test history) and its preferences are in `~/Library/Preferences`. Restore anything you still want from the Quarantine **before** you delete that folder: it holds the only copy of what Vutidy moved there.
