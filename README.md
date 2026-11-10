<p align="center"><img src="docs/assets/brand/logo-mark-256.png" alt="Vutidy" width="96"></p>

<h1 align="center">Vutidy</h1>

<p align="center"><b>SAFE · CLEAN · UNDOABLE</b><br>A native macOS cleaner and optimizer with a first-class module for developer clutter.</p>

Vutidy finds the space your Mac is wasting (caches, logs, build artifacts, Docker images, old node_modules, duplicates, leftovers of removed apps), shows you exactly what it would remove and the command it would run, and moves it to a **Quarantine** you can restore from for 7 days. Nothing is deleted for good unless you choose that.

It is written in Swift and SwiftUI, runs on macOS 13 or later, has no telemetry, and is not distributed through the Mac App Store (the sandbox would block most of what it does).

## Features

| Area | What it does |
| --- | --- |
| **Smart Scan** | One button: scans System Junk, Dev Junk, Trash, launch items and heavy processes together. |
| **Cleanup** | System Junk, **Dev Junk** (Docker, JetBrains, Node, Go, PHP, Python, Xcode, Homebrew, Gradle, Cargo, LLM models), Trash, Privacy (browser caches). |
| **Protection** | Persistence scanner with code-signature checks and a real-time monitor of sensitive folders. It is **not** an antivirus. |
| **Speed** | Optimization (CPU and memory gauges, heavy processes, startup items on/off), Maintenance (DNS, Spotlight, Time Machine snapshots, Launch Services). |
| **Applications** | Uninstaller with leftovers found by bundle ID, update check for Homebrew casks. |
| **Files** | Space Lens (bubble chart: area = size, colour = size, ring = status), Large & Old Files, Duplicates, iCloud Cloud Cleanup. |
| **Safety** | Hard blocklist, dry-run everywhere, Quarantine with undo, audit log, "commands to run" always visible. |
| **Menu bar** | Popover with recommendations, disk, memory, CPU, battery, network, speed test and Bluetooth battery. |
| **Keyboard** | Every page has a shortcut you can change, plus a Quick Open palette (⌘K). |
| **Languages** | English, Tiếng Việt, 日本語, 中文. |
| **CLI** | `vutidy-cli` scans and cleans from a terminal (dry-run by default). |

## Download

Get the newest release from the [Releases page](https://github.com/vunguyenvu35/vutidy/releases/latest), or use the stable links, which always point to the newest version:

- [`vutidy-macos.dmg`](https://github.com/vunguyenvu35/vutidy/releases/latest/download/vutidy-macos.dmg): open it and drag **Vutidy** onto *Applications*.
- [`vutidy-macos.zip`](https://github.com/vunguyenvu35/vutidy/releases/latest/download/vutidy-macos.zip): the same app as a zip.
- [`SHA256SUMS`](https://github.com/vunguyenvu35/vutidy/releases/latest/download/SHA256SUMS): check a download with `shasum -a 256 -c SHA256SUMS --ignore-missing`.

The app is universal (Apple silicon and Intel) and needs macOS 13 or later. Until releases are signed with an Apple Developer ID, macOS asks you to confirm the first launch: see [Installing on macOS](docs/getting-started/install-macos.md). Releases are built by GitHub Actions; see [Releasing](docs/development/release.md).

## Run it

You need Xcode or the Command Line Tools with Swift 5.9 or later.

```bash
swift build
swift run Vutidy                  # the app (window + menu bar popover)
swift run vutidy-cli scan dev     # the command line tool
swift test                        # the automated tests
scripts/make-app.sh               # builds dist/Vutidy.app with its icon (ad-hoc signed)
```

To scan Mail, Photos or Safari data, Vutidy needs **Full Disk Access**, and macOS only lists an app that runs as a real `.app`. Build `dist/Vutidy.app` with `scripts/make-app.sh` and add that app in *System Settings → Privacy & Security → Full Disk Access* (see [Getting started](docs/user-guide/01-getting-started.md#full-disk-access)).

## Documentation

Start at the [documentation index](docs/README.md). The most useful pages:

- [User guide](docs/user-guide/README.md): every screen, chapter by chapter.
- [Keyboard shortcuts](docs/user-guide/11-shortcuts.md)
- [Quarantine and safety](docs/user-guide/08-quarantine-and-safety.md): what Vutidy will never touch, and how undo works.
- [Development guide](docs/development/development.md)
- [Release notes](RELEASE_NOTES.md) · [Security policy](SECURITY.md)

## Support Vutidy

<p align="center">
  <b>Vutidy is free, has no ads and no telemetry, and is built in spare time.</b><br>
  If it saved you disk space or time, a coffee helps keep it going.
</p>

<p align="center">
  <a href="https://ko-fi.com/vunguyenvu"><img src="https://img.shields.io/badge/Ko--fi-Buy%20me%20a%20coffee-FF5E5B?style=for-the-badge&logo=ko-fi&logoColor=white" alt="Support Vutidy on Ko-fi"></a>
</p>

<p align="center">
  <sub>A one-off tip is plenty. Nothing is locked behind a donation, and it never changes what the app does.<br>
  Not into coffee? Star the repo, report a bug or improve a translation, which helps just as much.<br>
  The same link is in the app: <i>Settings → Support Vutidy</i> and the Help menu · <a href="docs/user-guide/14-support.md">More about supporting Vutidy</a></sub>
</p>

<!-- CRYPTO-DONATE: hidden for now, mirrors Vutty. Set showCryptoDonate to true in the app to show it there too.

| Network | Address |
| --- | --- |
| USDT · Tron (TRC20) | `TMXXHRNG7qauoFWJKYbqEbd4FGgt3DgjBK` |
| USDT · BSC (BEP20) | `0x4bdfd1d6456c28d06e3f8456ddac59e6168e5153` |

<img src="docs/assets/donate/usdt-tron.png" alt="USDT Tron QR" width="160"> <img src="docs/assets/donate/usdt-bsc.png" alt="USDT BSC QR" width="160">
-->

## Status

Version 0.1.0, pre-release. Read the [release notes](RELEASE_NOTES.md#known-issues) for what is verified and what is not, before you let it delete anything you care about. Start with *Preview only* mode.
