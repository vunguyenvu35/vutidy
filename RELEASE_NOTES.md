<p align="center"><img src="docs/assets/brand/logo-mark-256.png" alt="Vutidy" width="88"></p>

# Vutidy 0.3.0

Release date: 2026-11-10 · Platform: macOS 13 or later (only tried on Apple Silicon) · Status: **pre-release**. The [known issues of 0.1.0](#vutidy-010) still apply.

## What's new in 0.3.0

- **Smart Care.** Smart Scan now ends with **Your Mac's health**: five groups (Cleanup, Protection, Performance, Applications, Large & Old Files), each with one line and a **Review** button. It also runs the malware check, looks for Homebrew updates and apps you have not opened for 90 days, and finds large old files in Downloads. Only Cleanup is acted on by *Clean*; the other groups just report.
- **See what opens at login.** *Optimization → Opens at login* lists the apps that start with macOS, whether each is on, and which ones point to a file that is gone. **Manage** opens *System Settings → Login Items* (macOS lets only you flip those switches). No administrator password is asked.
- **Grant Full Disk Access with a guide.** *Grant access…* opens System Settings and a small panel beside it with the app icon to drag into the list, notices when you are done, and offers **Restart Vutidy**. **Reset permission** clears a stuck permission (`tccutil reset`) first.
- **Smart Scan fits small windows.** The hero drops its picture, then the ring, instead of pushing the page past the window edge.
- **Menu bar popover** no longer leaves a blank area at the top after you hide a recommendation.
- **Help → Check for Updates…**, and a card in the sidebar that stays visible while a new version is available or installing.
- Plan for what comes next: [malware checks and startup control](docs/development/plan-security-and-startup.md).

# Vutidy 0.2.1

Release date: 2026-11-10 · Platform: macOS 13 or later (only tried on Apple Silicon) · Status: **pre-release**. The [known issues of 0.1.0](#vutidy-010) still apply.

## What's new in 0.2.1

- **An update card that stays in view.** When a new version exists, a card at the bottom of the sidebar (and a dot on the gear) says so on every page; it shows the progress while Vutidy updates itself. Click it to open *Settings → General → Updates*.
- **Help → Check for Updates…** opens Settings and checks at once.
- **Smart Scan** lists *What will be cleaned*, open by default, so you see each group and its size before you press *Clean*. The confirmation also summarises the biggest groups.
- **Menu bar popover** closes after you press one of its buttons (for example *Free up memory*).
- **Space Lens**: the legend under the bubble chart is centred.
- Fixed untranslated text ("About Vutidy", the *Navigation*/*Actions* headers of the shortcut list, *Other* in the Uninstaller) and an empty gap above *Smart Scan* in the View menu.
- Fixed the **Select all / Deselect all** button on the cleanup pages (now a pill with an icon).
- Fixed the empty bar that short drop-down lists (such as the filters of *Large & Old Files*) showed.
- New **README** with the download first, and the stable download links work again (releases below 1.0 are no longer marked as pre-releases, which made GitHub's "latest" answer 404).

# Vutidy 0.2.0

Release date: 2026-11-10 · Platform: macOS 13 or later (only tried on Apple Silicon) · Status: **pre-release**. The [known issues of 0.1.0](#vutidy-010) still apply.

## What's new in 0.2.0

- **Update Vutidy from inside the app.** Settings → General checks the GitHub releases (every 24 hours if you allow it, or on demand), shows what is new, and installs the update after it verifies the SHA-256 and the code signature. The menu bar popover has a *Check for Updates…* item and a toast when a new version exists.
- **Space Lens, new scan screen.** A radar animation with live counters for files, size and speed, and the folder being read.
- **Space Lens, pinned action bar.** When you select items, a bar stays at the bottom with *Move to Quarantine* and the new *Delete permanently*, so you no longer scroll back up in a long list. *Deselect* (or Esc) hides it.
- **Space Lens, multi-select** in the list view: checkboxes, select all, ⌘-click to add or remove items and ⇧-click for a range. The actions apply to every selected item.
- **Space Lens, creation date** in the list and in the detail card.
- **Space Lens, "…more items"** now opens the containing folder in Finder instead of a path that does not exist.
- **Confirm dialogs** (used everywhere) are redesigned: frosted-glass card, glowing icon, two equal-width buttons, Esc to cancel and Return to confirm.
- **Menu bar popover, Devices tile** lists every connected Bluetooth device with a type icon, its name and its battery when the device reports one. Devices without a battery level (for example Logitech mice) were dropped before.
- **Smart Scan** can show the groups it will clean (*Review items*).
- Fixed the empty bar that short selection lists (for example the language picker) showed.

# Vutidy 0.1.0

Release date: 2026-11-10 · Platform: macOS 13 or later (only tried on Apple Silicon) · Status: **pre-release**. Read [Known issues](#known-issues) first.

## What's in 0.1.0

- **Smart Scan** that combines System Junk, Dev Junk, Trash, persistence and speed hints, with *Clean* for safe items and *Preview (dry-run)*.
- **Cleanup pages** (System Junk, Dev Junk, Trash, Privacy) with category cards, safety levels, filter chips, a pinned action bar, the list of commands to run and four clean modes.
- **Dev Junk**: Docker, JetBrains (including older IDE versions), Node (npm, Yarn, pnpm), Go, PHP, Python, Xcode, Homebrew, Gradle, Cargo, CocoaPods, Ollama and Hugging Face models, and stale `node_modules`/`vendor`/`target`/`.venv`/`Pods` in project folders you choose.
- **Safety layer**: hard blocklist (system folders, `~/Documents`, `~/Desktop`, keychains, `.ssh`…), Quarantine with exact-path restore and 7-day retention, audit log, dry-run in every mode, running-app checks.
- **Protection**: a persistence scanner with code-signature checks, and a real-time FSEvents monitor of sensitive folders. It is not an antivirus.
- **Speed**: Optimization (CPU, memory and startup gauges, heavy processes with Quit, startup items on/off) and Maintenance (DNS, purge, Spotlight, Time Machine snapshots, Launch Services, disk verify).
- **Applications**: Uninstaller with leftovers by bundle ID, and Updates for Homebrew casks.
- **Files**: Space Lens (bubble chart, treemap and list, with a scope picker and live progress), Large & Old Files, Duplicates (size, partial hash, full SHA-256), iCloud Cloud Cleanup.
- **Menu bar popover**: recommendations with ‹ › buttons, disk, memory, CPU, battery, network, speed test and Bluetooth battery.
- **Settings** in a floating window modelled on Vutty: General, Cleaning, Protection, Shortcuts, Storage and Support.
- **Customizable keyboard shortcuts** for every page and a **Quick Open** palette (⌘K), with conflict detection.
- **Four languages**: English, Tiếng Việt, 日本語, 中文, with *Automatic* following the system.
- **Donate card** with a Ko-fi link (Settings → Support Vutidy, Help → Support Vutidy).
- **Command line**: `vutidy-cli` (scan, clean with dry-run by default, space, duplicates, large, quarantine, audit).
- **CleanMyMac-style redesign** on a shared design system (solid coloured page icons, hero, cards, action bar) and a new logo.
- Automated tests (swift-testing) for the safety layer, scan engine, rule engine, modules and localization.

## Known issues

Verified by tests: the safety layer, scan engine, rules, duplicates, uninstaller leftovers, recommendations and the translation tables. **Not yet seen by hand end to end** (see the [test plan](docs/development/test-plan.md)):

- Most screens were built and compiled, and only a few were opened and looked at; none has been through a full real clean on a lived-in Mac. **Start with *Preview only*, then Quarantine.**
- The Settings window, the shortcut recorder, Quick Open and the Donate card follow the design but have not been run through the manual checklist.
- The menu bar popover, the real-time monitor under load, Space Lens on very large disks and Cloud Cleanup have not been exercised on real data.
- Intel Macs have not been tried.
- Administrator tasks use the macOS password prompt; behaviour on managed Macs is untested.

## Not implemented yet

- A privileged helper (so system-level files and `/Library` leftovers can be removed without prompts).
- Malware signatures (YARA), Endpoint Security blocking, login-item / cron / profile / browser-extension inspection.
- Scheduled scans and notifications; a first-run onboarding for Full Disk Access.
- Privacy cleanup of history and cookies, a TCC permission viewer, an Extensions manager, Shredder.
- Sparkle and App Store update checks; Google Drive / OneDrive / Dropbox eviction.
- CPU temperature, iPhone battery, APFS clone detection, light mode.
- A notarized, signed download and in-app updates; the app is built from source and signed ad hoc.
- The command line prints in Vietnamese only.

## Upgrading

There is no previous version. Your Quarantine and audit log live in `~/Library/Application Support/Vutidy` and are kept across builds.
