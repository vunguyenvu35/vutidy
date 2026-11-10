# Manual test plan

What the automated tests cannot cover: the real GUI, real system folders and macOS permissions. Run it on a real Mac (ideally a spare user account or a macOS VM) before a release. Tick each box; write down the macOS version and the build.

> **Safety first:** use *Preview only* until a section tells you otherwise, set `VUTIDY_HOME` to a scratch folder for the CLI parts, and have a recent Time Machine backup.

## Contents

- [0. Setup](#0-setup)
- [1. Safety layer](#1-safety-layer)
- [2. Smart Scan](#2-smart-scan)
- [3. Cleanup pages](#3-cleanup-pages)
- [4. Protection](#4-protection)
- [5. Speed](#5-speed)
- [6. Applications](#6-applications)
- [7. Files](#7-files)
- [8. Menu bar popover](#8-menu-bar-popover)
- [9. Settings](#9-settings)
- [10. Shortcuts and Quick Open](#10-shortcuts-and-quick-open)
- [11. Languages](#11-languages)
- [12. Support (Donate)](#12-support-donate)
- [13. Command line](#13-command-line)
- [14. Permissions and packaging](#14-permissions-and-packaging)

## 0. Setup

- [ ] `swift build` and `swift test` pass on a clean checkout.
- [ ] `scripts/make-app.sh` produces `dist/Vutidy.app` with the V icon and the name *Vutidy* (check in Finder and the Dock).
- [ ] The app opens with Smart Scan selected and no crash in the Console.

## 1. Safety layer

- [ ] Create a file in `~/Documents` and one in `~/Desktop`; try to remove them via Space Lens → Move to Quarantine. Both are refused (*blocked*).
- [ ] Quarantine a test file; it disappears from its place, appears in Quarantine with a days-left ring; **Restore** returns it to the exact path with the same permissions.
- [ ] Restore when a new file exists at the original path: refused, nothing overwritten.
- [ ] Set retention to 1 day, change a Quarantine entry's date in `index.json` to 2 days ago, restart: it is expired and removed.
- [ ] *Preview only* never changes files and still writes the audit log (`vutidy-cli audit`).
- [ ] The audit log lists every action with its mode and result.
- [ ] A symlink pointing at `/System` placed in a scanned folder cannot be removed.

## 2. Smart Scan

- [ ] **Start scanning** finds items, the hero ring and the three cards fill in, the sidebar shows no stale data.
- [ ] **Preview (dry-run)** changes nothing and reports a size.
- [ ] **Clean** with Quarantine moves only *Safe* items; the toast has *Undo*.
- [ ] Rescan after cleaning shows the cleaned size gone.

## 3. Cleanup pages

For each of System Junk, Dev Junk, Trash and Privacy:

- [ ] The ScanHero shows before the scan; the page scans on first open.
- [ ] Category cards show an icon, name, count, bar, size; expanding shows paths or `$ commands`.
- [ ] The circle selects or unselects a whole card; *Select all / Deselect all* work; filter chips *All / Safe / Review* show the right counts and lists.
- [ ] The **action bar** is pinned at the bottom, never clipped, at a small window size and a large one.
- [ ] **Command details** lists the real commands; the mode menu changes the text.
- [ ] ⌘↩ triggers Clean; turning off *Confirm before cleaning* skips the dialog.
- [ ] Trash page: Clean deletes for good after a clear confirmation.
- [ ] Dev Junk with Docker running: images, build cache, containers, volumes appear; with Docker stopped nothing is shown. Add a project folder in Settings and see stale `node_modules` offered as *Review*.
- [ ] A running JetBrains IDE or Xcode hides its caches.
- [ ] Without Full Disk Access Mail/Photos/Safari items are missing and the banner explains why.

## 4. Protection

- [ ] **Scan persistence** lists launch items; an unsigned test plist you create in `~/Library/LaunchAgents` is flagged.
- [ ] Switch real-time on; copy a `.dmg` or `.pkg` into Downloads: an alert appears after about two seconds. A new plist in LaunchAgents always alerts.
- [ ] The top-bar switch, the Protection switch and the popover switch stay in sync; ⌘⇧R toggles it.
- [ ] The page states clearly it is not an antivirus.

## 5. Speed

- [ ] The three gauges update every few seconds and look right next to Activity Monitor.
- [ ] **Quit app** quits a normal app; there is no button for Finder, helpers or Vutidy.
- [ ] The startup-item switch turns a user launch agent off and on (verify with `launchctl list`); a `/Library` item asks for the macOS password.
- [ ] Filter chips show the right items.
- [ ] Each Maintenance task runs (flush DNS, verify disk at least); output appears; cancelling the password prompt fails gracefully.

## 6. Applications

- [ ] The Uninstaller lists apps with icons, sources and last-used dates; search works.
- [ ] Choose a throw-away app: leftovers are listed, Safe vs Review is sensible; **Remove** quarantines the app and leftovers and unloads its launch agent; restoring brings them back.
- [ ] Updates: **Check** lists outdated Homebrew casks (or says none); it never installs.

## 7. Files

- [ ] Space Lens: treemap and list agree; double-click drills down; breadcrumb goes back; Docker.raw shows the warning.
- [ ] Large & Old Files filters by type, size and age; nothing preselected.
- [ ] Duplicates finds two identical files and ignores two files that differ only in the middle; a hard link is not reported.
- [ ] Cloud Cleanup lists downloaded iCloud files (with Full Disk Access) and evicts one without deleting it from iCloud.

## 8. Menu bar popover

- [ ] The icon opens the popover; cards can be moved with **‹ ›** and the dots follow; **×** hides a card for 7 days.
- [ ] Disk, memory, CPU, battery, network, devices show plausible values; idle CPU of the app is low (< 2 % in Activity Monitor).
- [ ] **Speed test** returns a result and keeps history.
- [ ] **Open Vutidy** raises the main window; **Quit** exits.

## 9. Settings

- [ ] ⌘, opens Settings as a floating window; Esc, clicking outside and × close it; maximize works.
- [ ] Left menu shows PREFERENCES (General, Cleaning, Protection), ADVANCED (Shortcuts, Storage), HELP (Support Vutidy, version).
- [ ] General: language, reduce motion, confirm before cleaning, default mode and *start real-time at launch* take effect immediately and survive a restart.
- [ ] Cleaning: retention and stale days change behaviour; project folders can be added and removed.
- [ ] Protection: Full Disk Access shows the right state; the buttons work.
- [ ] Storage: sizes are right; **Show in Finder** opens the folders; **Empty Quarantine** asks first and empties.

## 10. Shortcuts and Quick Open

- [ ] Every default shortcut in the [shortcut table](../user-guide/11-shortcuts.md#default-shortcuts) opens its page, from any page and with a text field focused.
- [ ] Pointing at a sidebar item shows its shortcut.
- [ ] ⌘K opens Quick Open; typing filters; ↑ ↓ ↩ choose; Esc closes.
- [ ] ⌘R rescans a cleanup page and Smart Scan.
- [ ] Settings → Shortcuts: record a new key; it works at once and survives a restart.
- [ ] A key already used is refused and names its owner; a plain letter is refused; ⌘Q and ⌘W are refused; F-keys are accepted; Esc cancels recording.
- [ ] **Reset** and **Reset all** restore the defaults.

## 11. Languages

- [ ] Switch English → Tiếng Việt → 日本語 → 中文 from the globe menu: the sidebar, a cleanup page, Settings and the popover all change, with no clipped or untranslated text.
- [ ] *Automatic* follows the macOS language (change the system language, relaunch) and falls back to English for an unsupported one.
- [ ] Long strings in Japanese and Chinese do not truncate badly in the action bar and key rows.

## 12. Support (Donate)

- [ ] **Settings → Support Vutidy** shows the Donate card; the Ko-fi button opens `https://ko-fi.com/vunguyenvu` in the browser.
- [ ] **Help → Support Vutidy** does the same.
- [ ] No crypto addresses are visible while `showCryptoDonate` is false.
- [ ] Nothing opens by itself and there is no nag.

## 13. Command line

- [ ] `vutidy-cli scan all` lists items; `clean system` is a dry run; `--mode quarantine` moves safe items; `quarantine list` and `restore <ID>` undo it; `audit` shows the history.

## 14. Permissions and packaging

- [ ] `swift run Vutidy` shows the banner; the packaged app can be added to Full Disk Access and then scans Safari and Mail.
- [ ] After a rebuild the grant may need re-adding (ad-hoc signature): confirm the behaviour is described in Troubleshooting.
- [ ] Gatekeeper's *Open Anyway* flow works for a downloaded copy.
