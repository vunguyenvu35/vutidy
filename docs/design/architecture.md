# Plan: a macOS cleaner and optimizer (original design)

> This is the **first design document, kept as written** (revision 2, translated into English) and then annotated. The project is now named **Vutidy**. Read [What changed when it was built](#what-changed-when-it-was-built) first, then the plan, for the gap between intent and reality.
> Reference for features: CleanMyMac X / CleanMyMac 5. Only the *features* are cloned; no name, logo or UI of the reference product is used.

## Contents

- [What changed when it was built](#what-changed-when-it-was-built)
- [1. Goals](#1-goals)
- [2. Feature map](#2-feature-map)
- [3. Architecture](#3-architecture)
- [4. Scan engine](#4-scan-engine)
- [5. Rule engine](#5-rule-engine)
- [6. Safety layer](#6-safety-layer)
- [7. Modules in detail](#7-modules-in-detail)
- [8. Permissions and distribution](#8-permissions-and-distribution)
- [9. Roadmap](#9-roadmap)
- [10. Testing](#10-testing)
- [11. Risks](#11-risks)
- [12. Open questions](#12-open-questions)

## What changed when it was built

| Plan | What was built | Why |
| --- | --- | --- |
| Rules in YAML | Rules in **JSON** (`Sources/RuleEngine/Resources/rules.json`, user rules in `~/Library/Application Support/Vutidy/Rules/*.json`) | No third-party dependency (a YAML parser) for a file that is only a list of objects |
| Quarantine index and scan cache in SQLite (GRDB) | The Quarantine index is a **JSON file** next to the quarantined items; there is no scan cache yet | Fewer moving parts; the index is small. Scan cache can come later |
| Duplicate hashing with xxHash3 or BLAKE3 | **SHA-256** (CryptoKit) | System framework, no dependency; fast enough for the partial-then-full strategy |
| Privileged helper (`SMAppService.daemon` + XPC) | **Not built.** Administrator tasks use the macOS password prompt (`osascript … with administrator privileges`) | Needs a signed helper; planned for later |
| File walker with `getattrlistbulk` | `lstat` + `readdir` walker with hard-link de-duplication | Simple and correct first; faster walker is an optimization |
| YARA malware signatures | **Not built.** Protection is a persistence scanner with signature checks plus a real-time monitor | Matches the honest "not an antivirus" scope |
| Sparkle / App Store update check | Homebrew casks only | |
| CPU temperature, iPhone battery | **Not built** (private APIs) | |
| Localization (i18n vi/en in phase 6) | **Built early**: English, Tiếng Việt, 日本語, 中文, switchable at runtime | See [Languages](../user-guide/12-languages.md) |
| Phase order | Dev Junk first, then Space Lens etc.; the popover and settings came after the redesign | Dev Junk is the differentiator, so it was built first |
| Smart Scan scheduler | Not built | |
| CLI "open question" | **Built**: `vutidy-cli` | Cheap once the engine was a library |

Additions that the plan did not have: a Quick Open palette and customizable shortcuts, a Settings window modelled on Vutty, a Donate card, a CleanMyMac-style redesign (see the [design spec](design-spec.md)), and a hard test suite for the safety layer.

## 1. Goals

- Clone the feature groups of a commercial cleaner: junk cleanup, space management, uninstaller, performance tuning, protection, system monitoring.
- **Differentiator:** a cleanup module for developers (Docker, JetBrains, Go, Node, PHP, Xcode, Homebrew, LLM models).
- **Safety first:** never delete permanently right away, every action can be undone.
- Native, light, fast. No telemetry by default.

### Non-goals (first phase)

- Not a full antivirus. Real-time protection in v1 relies on **FSEvents** only (detects after the file is written), **not** Endpoint Security / System Extensions.
- iPhone battery via the private `MobileDevice` API is experimental and off by default.
- Not on the Mac App Store (the sandbox blocks most of the features).
- No support for macOS earlier than 13.

## 2. Feature map

| Group | Feature | Description | Needs root |
| --- | --- | --- | --- |
| Smart Scan | Smart Scan | One-button combined scan | Partly |
| Cleanup | System Junk | User/system caches, logs, language files, broken prefs, broken login items | Partly |
| Cleanup | Mail Attachments | Downloaded Mail attachments | No |
| Cleanup | Photo Junk | Photos library cache/thumbnails | No |
| Cleanup | Trash Bins | User, external-volume and per-app Trash | Partly |
| Cleanup | **Dev Junk** | Docker, IDE caches, build caches, package caches | No |
| Protection | Malware Removal | Signatures (YARA) + persistence scan | Partly |
| Protection | Privacy | Browser history/cookies, recent items, TCC permissions | No |
| Speed | Optimization | Login items, Launch Agents/Daemons, CPU/RAM hogs | Partly |
| Speed | Maintenance | Flush DNS, free purgeable RAM, reindex Spotlight, thin Time Machine snapshots | Yes |
| Applications | Uninstaller | Remove app + leftovers, reset app | Partly |
| Applications | Updater | App updates (Sparkle, Homebrew, MAS) | No |
| Applications | Extensions | Safari extensions, plugins, preference panes, Spotlight/QuickLook plugins | Partly |
| Files | Space Lens | Disk usage visualization (sunburst/treemap) | No |
| Files | Large & Old Files | Filter by size/age/type | No |
| Files | Duplicates | Find duplicates (size → partial hash → full hash) | No |
| Files | Shredder | Secure delete | No |
| Cloud | Cloud Cleanup | Evict local copies of iCloud/Google Drive/OneDrive | No |
| Monitor | Menu Bar Popover | Disk (with purgeable), RAM, battery, CPU load + temperature, Wi-Fi, quick actions | Partly |
| Monitor | Recommendations | Action cards from scan results and system state | No |
| Monitor | Connected Devices | Bluetooth device battery; iPhone (experimental) | No |
| Monitor | Speed Test | Network speed via `networkQuality` | No |
| Protection | Real-time Monitor | Scan new files in sensitive places via FSEvents | No |

## 3. Architecture

### 3.1 Tech stack

| Component | Choice | Why |
| --- | --- | --- |
| Language | Swift 5.9+ | Direct access to system APIs, good concurrency |
| UI | SwiftUI (+ AppKit when needed) | Native, light |
| Min OS | macOS 13 Ventura | `SMAppService`, stable SwiftUI |
| Privileged ops | `SMAppService.daemon` + XPC | What Apple recommends instead of `SMJobBless` |
| App updates | Sparkle 2 | Standard outside the MAS |
| Malware rules | YARA (libyara via C interop) | Industry standard, community rules |
| Storage | SQLite (GRDB) | Action history, quarantine index, scan cache |
| Build | SPM, xcodebuild, GitHub Actions | Easy-to-test packages |

### 3.2 Components

```
┌──────────────────────────────────────────────────────────┐
│                     App (SwiftUI)                        │
│  SmartScan │ Cleanup │ Protection │ Speed │ Apps │ Files │
└───────────────┬──────────────────────────────┬───────────┘
                │                              │
        ┌───────▼────────┐            ┌────────▼────────┐
        │  Core Package  │            │  Menu Bar Agent │
        │ ScanEngine     │            │ (LaunchAgent)   │
        │ RuleEngine     │            └─────────────────┘
        │ SafetyLayer    │
        │ ActionExecutor │
        └───────┬────────┘
                │ XPC (verify code signature)
        ┌───────▼────────────┐
        │ Privileged Helper  │  (root, SMAppService.daemon)
        │ - delete system    │
        │ - flush DNS        │
        │ - purge            │
        │ - tmutil thin      │
        └────────────────────┘
```

### 3.3 Package layout

```
Sources/
├── CoreKit/            # shared models, logging, utils
├── ScanEngine/         # file walker, size calculator
├── RuleEngine/         # load + evaluate rules
├── SafetyLayer/        # blocklist, quarantine, undo, dry-run
├── Modules/
│   ├── SystemJunk/ DevJunk/ Uninstaller/ SpaceLens/ LargeOldFiles/ Duplicates/
│   ├── Maintenance/ Optimization/ Privacy/ Malware/ Updater/ CloudCleanup/
│   └── Recommendations/ RealtimeMonitor/ DeviceMonitor/
├── HelperProtocol/     # XPC protocol shared by app and helper
├── PrivilegedHelper/   # helper target
└── MenuBarAgent/       # agent target
Rules/                  # *.yaml rule definitions (ship with the app, updatable)
```

(The built layout is described in [Clean architecture](clean-architecture.md).)

### 3.4 Module interface

```swift
protocol CleanerModule {
    var id: String { get }
    var requiresPrivilege: Bool { get }
    func scan(progress: ScanProgress) async throws -> [ScanItem]
    func clean(_ items: [ScanItem], mode: CleanMode) async throws -> CleanReport
}

enum CleanMode { case dryRun, moveToTrash, quarantine, permanent }

struct ScanItem: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let allocatedSize: Int64
    let category: String
    let ruleID: String
    let safety: SafetyLevel   // .safe, .review, .dangerous
    var selected: Bool
}
```

## 4. Scan engine

- **File walker:** `getattrlistbulk` (much faster than `FileManager.enumerator`) with `fts` as a fallback.
- **Concurrency:** a `TaskGroup` per first-level directory, with a cap on parallel tasks so I/O does not stall.
- **Size:** use `allocatedSize` (`ATTR_FILE_ALLOCSIZE`), not logical size. APFS clones and purgeable space mean totals must be labelled as estimates.
- **Hard links:** de-duplicate by `(dev, ino)`.
- **Result cache:** store a snapshot in SQLite so the next scan only walks diffs, based on directory mtime.
- **Cancel/progress:** support cancelling mid-way and stream progress to the UI.

## 5. Rule engine

Rules are separate from code and ship as data so they can be updated without releasing the app.

```yaml
- id: user-caches
  module: system-junk
  title: "User cache files"
  paths:
    - "~/Library/Caches/*"
  exclude:
    - "~/Library/Caches/com.apple.*"
    - "~/Library/Caches/CloudKit"
  conditions:
    min_age_days: 0
    app_not_running: true      # skip caches of running apps
  safety: safe
  action: trash

- id: jetbrains-orphan-config
  module: dev-junk
  title: "Config/cache of removed or old IDE versions"
  detector: jetbrains_orphans   # needs custom logic → call a detector
  safety: review
  action: trash
```

Safety levels:

| Level | Default behaviour |
| --- | --- |
| `safe` | Selected by default |
| `review` | Shown but not selected |
| `dangerous` | Shown only, needs a separate confirmation |

## 6. Safety layer (mandatory from Phase 0)

- **Hard blocklist:** `/System`, `/usr` (except `/usr/local` with an explicit rule), `/bin`, `/sbin`, `~/Documents`, `~/Desktop`, the originals of the Photos library, keychains, `.ssh`, `.gnupg`, and everything SIP-protected.
- **Default:** move to the Trash (`FileManager.trashItem`). System files go to a quarantine folder `~/Library/Application Support/<app>/Quarantine/` with an index.
- **Quarantine retention:** 7 days (configurable), then deleted automatically.
- **Undo:** restore from quarantine to the exact original path, keeping permissions and xattrs.
- **Dry-run mode:** every module must support it.
- **Audit log:** record every delete/move (path, size, rule, time).
- **Running apps:** never touch the caches, containers or prefs of a running app.

## 7. Modules in detail

### 7.1 System Junk

- User cache `~/Library/Caches`; system cache `/Library/Caches` (via helper).
- Logs: `~/Library/Logs`, `/Library/Logs`, `/private/var/log` (rotated files only).
- Language files: unused `*.lproj` in app bundles. **Warning:** this breaks the code signature, so off by default or only for unsigned apps.
- Broken preferences (unparsable plist); broken login items (point to a missing app).
- Xcode junk moves to Dev Junk.

### 7.2 Dev Junk (the main differentiator)

| Source | Detection | Action |
| --- | --- | --- |
| Docker | `docker system df -v` | `docker image prune`, `docker builder prune`, `docker volume prune` (volumes are `review`), suggest compacting `Docker.raw` |
| JetBrains | `~/Library/Caches/JetBrains`, `~/Library/Logs/JetBrains`, `~/Library/Application Support/JetBrains/<IDE><version>` | Delete caches; detect removed or old IDE versions |
| Go | `go env GOCACHE GOMODCACHE` | `go clean -cache`, `go clean -modcache` (`review`) |
| Node | npm/yarn/pnpm caches, project `node_modules` | Delete caches; list `node_modules` of projects with mtime older than N days |
| PHP | `~/.composer/cache`, old project `vendor/` | Like Node |
| Python | `~/Library/Caches/pip`, `__pycache__`, old venvs | Like Node |
| Xcode | DerivedData, Archives, iOS DeviceSupport, simulators | `xcrun simctl delete unavailable` |
| Homebrew | `brew --cache` | `brew cleanup -s` |
| LLM | `~/.ollama/models`, `~/.cache/huggingface` | List only, `review`, not preselected |

Project scan: the user picks the root folders (`~/Projects`, `~/Code`…); the whole home folder is never scanned.

### 7.3 Uninstaller

- List apps in `/Applications` and `~/Applications` with size, last-used date (`kMDItemLastUsedDate`) and source (MAS/Homebrew/other).
- Find leftovers by **bundle ID** and **app name** in `~/Library/{Application Support, Caches, Preferences, Containers, Group Containers, Saved Application State, HTTPStorages, WebKit, Logs, LaunchAgents, Cookies}` and `/Library/{Application Support, LaunchAgents, LaunchDaemons, PrivilegedHelperTools, Preferences}`; receipts via `pkgutil`.
- Actions: Uninstall, Reset (data only, keep the app), remove leftovers of a previously removed app.
- Unload launch agents/daemons first (`launchctl bootout`). For Homebrew apps, suggest `brew uninstall --cask`.

### 7.4 Optimization

- Login items: `SMAppService` status for modern apps; the BTM database (`sfltool dumpbtm`, read-only) to list them.
- Launch Agents/Daemons: list plists, loaded state, enable/disable (never delete).
- Heavy consumers: `proc_pid_rusage`, `proc_pidinfo` for top CPU/RAM/energy over a period.

### 7.5 Maintenance

| Task | Command/API | Keep? |
| --- | --- | --- |
| Flush DNS | `dscacheutil -flushcache; killall -HUP mDNSResponder` | Yes |
| Free RAM | `purge` | Yes (explain the limited effect) |
| Reindex Spotlight | `mdutil -E /` | Yes |
| Thin TM local snapshots | `tmutil listlocalsnapshots`, `tmutil thinlocalsnapshots` | Yes |
| Rebuild Launch Services | `lsregister -kill -r -domain local -domain system -domain user` | Yes |
| Periodic scripts | `periodic daily weekly monthly` | No, deprecated |
| Repair disk permissions | n/a | No, meaningless since SIP |
| Verify disk | `diskutil verifyVolume /` | Yes (verify only) |

### 7.6 Space Lens

Build the tree from the scan engine, compute sizes bottom-up. Visualization: sunburst (Canvas/SwiftUI) or squarified treemap. Drill-down, breadcrumb, "Reveal in Finder", move to Trash. Per-volume scanning, external drives supported.

### 7.7 Large & Old Files

Filter by size > N, not opened for > N days (`kMDItemLastUsedDate`, fall back to `atime`), by type (archive, video, disk image, installer). Suggest groups: `.dmg`/`.pkg` in Downloads, big videos, old archives.

### 7.8 Duplicates

1. Group by size (ignore files < 1 KB).
2. Partial hash (first 4 KB + last 4 KB).
3. Full hash (xxHash3 or BLAKE3) for remaining candidates.
4. Recognize APFS clones (no extra space) and mark them separately.
5. Suggest keeping the oldest copy or the one in a preferred folder.

### 7.9 Privacy

- Browsers (Safari, Chrome, Firefox, Arc, Edge, Brave): history, cookies, cache, form data. Read/delete SQLite; **requires the browser to be closed**.
- Recent items, Quick Look cache, Finder recents.
- TCC permissions: read `TCC.db` (needs FDA) to show which app has which permission; reset via `tccutil reset <service> <bundleID>`.

### 7.10 Malware / Protection

Realistic scope: **a persistence scanner and a signature scan**, not a real-time antivirus.

- Persistence: LaunchAgents/Daemons, login items, cron, kernel/system extensions, browser extensions, configuration profiles, `/etc/hosts`, DNS settings, authorization plugins.
- For each item check the code signature (`SecStaticCodeCheckValidity`), notarization and Team ID; flag unsigned or ad-hoc items.
- Signatures: YARA rules (community sources, updated periodically).
- Actions: disable, then quarantine, then delete (with undo).

#### Real-time Monitor (FSEvents)

- Runs in the menu bar agent with `FSEventStreamCreate` and `kFSEventStreamCreateFlagFileEvents`.
- Watched: `~/Downloads`, `~/Desktop`, `/Applications`, `~/Applications`, `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`, `/Library/PrivilegedHelperTools`.
- Pipeline: event → debounce (file still being written) → filter by type (Mach-O, app bundle, `.dmg`, `.pkg`, script, persistence plist) → YARA scan + code-signature check.
- A new file in `LaunchAgents`/`LaunchDaemons` always raises an alert, even if clean, because it is the most common persistence channel. Also check the `com.apple.quarantine` xattr to know it was downloaded.
- UI: ON/OFF state, "Last file scanned", signature DB update time, a Check Now button.
- Resource limits: bounded queue, skip files > 500 MB (configurable), low priority (`QoS .utility`).
- **State the limit in the UI:** it only detects after the file is written and cannot block execution. Blocking needs Endpoint Security (v2, requires an Apple entitlement).

### 7.11 Updater

Sparkle: read `SUFeedURL` from `Info.plist` and parse the appcast. MAS apps: iTunes Lookup API by bundle ID. Homebrew casks: `brew outdated --cask --greedy`. Others: compare versions against a known source (best effort). Only notify and open the download or MAS page; do not install (first phase).

### 7.12 Cloud Cleanup

iCloud Drive: `FileManager.evictUbiquitousItem(at:)`. File Provider (Google Drive, OneDrive, Dropbox): `NSFileProviderManager` evict if the provider supports it. Only the local copy is evicted; nothing is deleted in the cloud.

### 7.13 Menu Bar Popover

Three zones: **Recommendations** (horizontal carousel), **Overview** (widget grid), **Footer** (open app, settings).

| Widget | Data | API / how | Quick action |
| --- | --- | --- | --- |
| Protection | Real-time state, last file scanned, DB update | Real-time Monitor (7.10) | Check Now |
| Disk | Available, purgeable | `volumeAvailableCapacityForImportantUsage`, `volumeAvailableCapacity`, `volumeTotalCapacity` | Free Up |
| Memory | Available, pressure, swap | `host_statistics64`, `vm.swapusage`, memory pressure source | Free Up (`purge` via helper) |
| Battery | %, charging, cycles, health | IOKit `IOPSCopyPowerSourcesInfo`, `AppleSmartBattery` | n/a |
| CPU | Load, temperature | `host_processor_info`; temperature: SMC (Intel) / `IOHIDEventSystemClient` (Apple Silicon, private) | Open heavy consumers |
| Wi-Fi | Up/down realtime, SSID | `getifaddrs` delta every 1–2 s; SSID via CoreWLAN (needs Location) | Test Speed |
| Connected Devices | Name + battery % | see 7.16 | n/a |

General requirements: the agent is a separate process, idle CPU < 1 %, RAM < 50 MB; polling only speeds up while the popover is open. CPU temperature on Apple Silicon uses a private API: wrap it behind a `SensorProvider` protocol and hide the widget on failure. Notifications: disk almost full, sustained high CPU, high memory pressure, sustained high temperature.

### 7.14 Smart Scan

An orchestrator that runs System Junk, Dev Junk (safe), Malware (persistence) and Optimization (hints) in parallel. Results merge into three cards: Cleanup, Protection, Speed. One "Run" button applies only `safe` items.

### 7.15 Recommendation Engine

Produces action cards (popover and main screen).

```swift
struct Recommendation: Identifiable {
    let id: String              // stable, to remember dismissal
    let priority: Int
    let icon: String
    let title: String           // "Free 13.95 GB of purgeable space."
    let actionTitle: String     // "Free Up Space"
    let action: RecommendationAction
}

protocol RecommendationProvider {
    func evaluate(context: SystemContext) async -> [Recommendation]
}
```

| Provider | Condition | Action |
| --- | --- | --- |
| Purgeable space | Purgeable > 5 GB | Thin TM snapshots / open Cleanup |
| Disk low | Free < 10 % | Open Space Lens |
| Old malware scan | No deep scan for > 7 days | Run Deep Scan |
| Big Dev Junk | Safe Dev Junk > 5 GB (from the last scan) | Open Dev Junk |
| App outdated | Updater has ≥ 1 update | Open Updater |
| Unused app | App not opened for > 90 days | Open Uninstaller |
| Many login items | > N login items/agents | Open Optimization |
| Battery health | Health < 80 % | Open battery info |

Evaluate periodically (30 minutes by default) and after each scan, using cached data only (never start a heavy scan). Dismiss: hide by `id` for N days (stored); show again if the condition gets significantly worse. Order by `priority`, at most 5 cards. Thresholds are data, like rules, so they can change without a release.

### 7.16 Connected Devices and Speed Test

**Connected Devices.** Bluetooth HID (mouse, keyboard, trackpad): IOKit service `AppleDeviceManagementHIDEventService`, key `BatteryPercent`. Headphones/AirPods: `system_profiler SPBluetoothDataType -json` (slow, only when the popover opens, cached 60 s). iPhone/iPad (**experimental, off by default**): private `MobileDevice` framework, paired devices only; may break on new macOS. Warn when a device battery is < 20 %.

**Speed Test.** `networkQuality -c` (macOS 12+), parse the JSON for download, upload and responsiveness (RPM). Run in the agent with progress, keep the last 20 results, never run automatically (bandwidth).

## 8. Permissions and distribution

| Item | How |
| --- | --- |
| Full Disk Access | Onboarding guide; check by trying to read `~/Library/Safari` or `TCC.db` |
| Privileged helper | `SMAppService.daemon`, the user approves in System Settings → Login Items |
| XPC security | The helper verifies the caller's code signature and Team ID (`setCodeSigningRequirement`, macOS 13+) |
| Signing | Developer ID Application, Hardened Runtime |
| Notarization | `notarytool` in CI |
| Updates | Sparkle 2 + EdDSA signature |
| Distribution | DMG + Homebrew cask |

## 9. Roadmap

| Phase | Content | Estimate (1 dev) | Deliverable |
| --- | --- | --- | --- |
| **0. Foundation** | Package structure, scan engine, rule engine, safety layer (quarantine/undo/dry-run), helper + XPC, FDA onboarding, notarization CI | 2–3 weeks | An empty app that scans and moves files safely |
| **1. Space MVP** | Space Lens, Large & Old Files, System Junk, Dev Junk, Trash Bins | 3–4 weeks | **First real usable build** |
| **2. App management** | Uninstaller + leftovers, Extensions, login items / launch agents | 2–3 weeks | |
| **3. Performance + Popover** | Maintenance, heavy consumers, menu bar popover (widgets + quick actions), Connected Devices (Bluetooth), Speed Test, basic Recommendation Engine | 3–4 weeks | Complete popover except Protection |
| **4. Extension** | Updater, Cloud Cleanup, Duplicates, Mail/Photo junk | 3 weeks | |
| **5. Protection** | Persistence scanner, YARA, Privacy cleaner, Real-time Monitor (FSEvents), Protection widget, malware provider | 4–5 weeks | |
| **6. Polish** | Smart Scan, scheduler, i18n vi/en, docs, release 1.0 | 2 weeks | v1.0 |

**Total:** about 19–24 weeks for one developer.

## 10. Testing

- **Unit tests:** rule engine, safety layer (the blocklist needs 100 % coverage).
- **Fixture file system:** build fake directory trees in a temp dir to test scan and clean.
- **VM tests:** run on a clean macOS VM (UTM/Tart) for everything that needs root.
- **Dry-run diff:** compare a dry run against the real operation.
- **Performance benchmark:** scanning a home directory of about 500k files, target < 30 s on an M1.

## 11. Risks

| Risk | Level | Mitigation |
| --- | --- | --- |
| Deleting user data by mistake | High | Safety layer from phase 0, quarantine, blocklist, `review` by default for anything uncertain |
| Malware module becoming "theatre" | Medium | Limit the scope, do not market it as antivirus |
| macOS API changes between versions | Medium | Rules separate from code, CI on several macOS versions |
| Deleting language files breaks signatures | Medium | Off by default |
| Trademark | Low | Do not use the name/logo/UI of the reference product |
| Wrong sizes from APFS clones/purgeable | Low | Use allocated size, label as an estimate |
| Private APIs (CPU temperature, MobileDevice) break on macOS updates | Medium | Wrap behind a protocol, hide the widget on failure; iPhone off by default |
| Users read the FSEvents monitor as real-time AV | Medium | State the limit in the UI and docs |
| Menu bar agent drains battery | Low | Adaptive polling, benchmark idle CPU in CI |

## 12. Open questions

- [ ] Goal: personal tool or a released product (open source / commercial)?
- [ ] Project name? **Decided: Vutidy.**
- [ ] Intel Mac support, or Apple Silicon only?
- [ ] Is Dev Junk in phase 1 right away or later? **Decided: first.**
- [ ] A CLI (headless) alongside the GUI? **Decided: yes, `vutidy-cli`.**
- [ ] Malware rules: write our own or use community YARA sources?
- [ ] Real-time Monitor: FSEvents for v1 and Endpoint Security for v2? *(assumed yes; built that way)*
- [ ] iPhone battery: keep as experimental or drop? *(not built)*
