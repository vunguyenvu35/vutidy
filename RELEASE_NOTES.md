<p align="center"><img src="docs/assets/brand/logo-mark-256.png" alt="Vutidy" width="88"></p>

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
