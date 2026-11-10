# Troubleshooting

## Contents

- [Vutidy is missing from Full Disk Access](#vutidy-is-missing-from-full-disk-access)
- [I granted Full Disk Access and it asks again after a rebuild](#i-granted-full-disk-access-and-it-asks-again-after-a-rebuild)
- [The window does not appear with swift run](#the-window-does-not-appear-with-swift-run)
- [Dev Junk does not show Docker, Go or Homebrew](#dev-junk-does-not-show-docker-go-or-homebrew)
- [An item was skipped as blocked](#an-item-was-skipped-as-blocked)
- [Restore says the path already exists](#restore-says-the-path-already-exists)
- [An administrator task did nothing](#an-administrator-task-did-nothing)
- [Sizes do not match Finder](#sizes-do-not-match-finder)
- [swift test fails with TestingMacros](#swift-test-fails-with-testingmacros)
- [Where your data lives](#where-your-data-lives)
- [Reset everything](#reset-everything)

## Vutidy is missing from Full Disk Access

You started it with `swift run Vutidy`. A bare executable has no bundle ID, name or icon, so macOS cannot list it as an app. Build the real app with `scripts/make-app.sh`, open `dist/Vutidy.app`, then use **+** in *Full Disk Access* (the banner's **Reveal app in Finder** shows where it is) and restart Vutidy.

## I granted Full Disk Access and it asks again after a rebuild

`scripts/make-app.sh` signs ad hoc, and an ad-hoc signature is different for every build, so macOS sees a new app. Remove the old entry, add the new `Vutidy.app`, or sign with a stable Developer ID (see [Development](../development/development.md#packaging)).

## The window does not appear with swift run

The app starts as a regular app and activates itself, but if your terminal keeps focus the window can open behind other windows. Click the Vutidy icon in the Dock, or use `dist/Vutidy.app`.

## Dev Junk does not show Docker, Go or Homebrew

A rule only appears when its tool is installed and reachable. Vutidy adds `/opt/homebrew/bin`, `/usr/local/bin` and common Go, Cargo and Docker paths to its search path because a GUI app has a short `PATH`. Check `which docker` in a terminal; if Docker Desktop is not running, `docker system df` fails and Docker shows nothing.

## An item was skipped as blocked

It is on the [blocklist](08-quarantine-and-safety.md#the-blocklist) (for example anything inside `~/Documents` or `~/Desktop`). This cannot be overridden on purpose.

## Restore says the path already exists

Something new is at the original location. Rename or move it, then restore again. Vutidy never overwrites.

## An administrator task did nothing

You dismissed the macOS password dialog, or the command failed; the output under the task says which. `purge` and `mdutil` can fail on managed Macs where administrator tasks are restricted.

## Sizes do not match Finder

Vutidy reports **allocated** size (disk blocks used), counts hard links once and does not follow symbolic links or other volumes. Finder reports logical size and treats purgeable space differently, so a difference is normal.

## swift test fails with TestingMacros

Occasionally the first `swift test` right after a `swift build` reports *external macro implementation type 'TestingMacros…' could not be found*. Run `swift test` again. If it persists, delete `.build` and rebuild.

## Where your data lives

| What | Where |
| --- | --- |
| Quarantine, audit log, custom rules, speed-test history | `~/Library/Application Support/Vutidy` (or `$VUTIDY_HOME`) |
| Preferences (language, settings, shortcuts) | `~/Library/Preferences` (the app's defaults) |
| Nothing else | There is no cloud, account or telemetry |

## Reset everything

Quit Vutidy, restore anything you still need from the Quarantine, then delete `~/Library/Application Support/Vutidy` and remove the app's defaults (for the packaged app: `defaults delete com.vutidy.app`).

## The banner stays after I turned Full Disk Access on

Check these in order:

1. **Are you running the real app?** If the banner only has an *Open System Settings* button, or says you are running the unpackaged build, you started `swift run Vutidy`. That process is not `Vutidy.app`, so the permission you granted to the app does not apply to it. Run `scripts/make-app.sh --open` and use `dist/Vutidy.app`.
2. **Restart the app.** macOS applies a new Full Disk Access grant only to processes started afterwards. Use **Restart Vutidy** on the banner (or in Settings → Protection). Closing the window is not enough: Vutidy keeps running in the menu bar, so it is still the old process. Quit it completely (**Vutidy → Quit Vutidy Completely**, ⌥⌘Q, or *Quit* in the menu bar popover) and open it again.
3. **Did you rebuild since you granted it?** An ad-hoc signed build gets a new identity every time, so the old toggle no longer matches. In *System Settings → Privacy & Security → Full Disk Access* remove Vutidy with **−**, add `dist/Vutidy.app` again with **+**, then restart. Signing with a fixed certificate (`CODESIGN_IDENTITY`) avoids this.

Vutidy checks the permission by trying to open files only Full Disk Access can read (the TCC database first). A file that does not exist, for example Safari data on a Mac that never used Safari, does not count as "denied".
