<p align="center"><img src="docs/assets/brand/logo-mark-256.png" alt="Vutidy" width="88"></p>

# Vutidy 0.10.0

Release date: 2026-11-20 · Platform: macOS 13 or later (only tried on Apple Silicon and one Intel Mac) · Status: **pre-release**. The [known issues of 0.1.0](#vutidy-010) still apply.

## What's new in 0.10.0

- **Updates are checked while Vutidy keeps running.** It used to look for a new version only when it opened. Now, once every 24 hours, it also checks while it sits in the menu bar, so a Mac that is never restarted still hears about new versions. Turn it off with *Settings → General → Check for updates automatically*.
- **Optional automatic install.** *Settings → General → Install updates automatically* (off by default). When a new version is found, Vutidy downloads it, checks the SHA-256 and the signature (the same checks as the **Update and restart** button), installs it and reopens. It only does this when you are not in the app (Vutidy is not the app in front) and nothing is scanning, cleaning or checking a file; otherwise it waits and tries again 10 minutes later. If an automatic install fails it tells you once and does not retry that version by itself, and **Update and restart** stays available.
- **A note after updating.** The first launch of the new version says *Vutidy updated to <version>*.

It is off by default for a reason: builds that are not signed with a Developer ID get a new signature with every version, so macOS may ask you to grant **Full Disk Access** again after each update. See [Updating Vutidy](docs/user-guide/16-updating-vutidy.md).

# Vutidy 0.9.2

Release date: 2026-11-20 · Platform: macOS 13 or later (only tried on Apple Silicon and one Intel Mac) · Status: **pre-release**. The [known issues of 0.1.0](#vutidy-010) still apply.

## What's new in 0.9.2

- **The Protection card names the file.** When the real-time monitor flags something, the card in the menu bar popover used to say only "1 item(s) to review". It now says which file ("To review: <name>"), in amber. Open *Protection* to quarantine, reveal or dismiss it. When the file is gone the alert disappears by itself and the card goes back to *Protected*.

# Vutidy 0.9.1

Release date: 2026-11-20 · Platform: macOS 13 or later (only tried on Apple Silicon and one Intel Mac) · Status: **pre-release**. The [known issues of 0.1.0](#vutidy-010) still apply.

## What's new in 0.9.1

- **No change to the app.** This release only fixes the developer build: `make build` now also copies the app for your Mac to `dist/Vutidy.app` and replaces the old one, so opening that path no longer runs a stale version. The separate `dist/arm64` and `dist/x86_64` apps are still made for packaging.

# Vutidy 0.9.0

Release date: 2026-11-20 · Platform: macOS 13 or later (only tried on Apple Silicon and one Intel Mac) · Status: **pre-release**. The [known issues of 0.1.0](#vutidy-010) still apply.

## What's new in 0.9.0

- **Check a file from the Real-time Monitor.** *Protection → Real-time Monitor → Check a file…* lets you pick any file or app and shows a verdict with the reasons, its code signature (Apple, App Store, notarized, not notarized, unsigned or broken), what Gatekeeper says, where it was downloaded from, its SHA-256 and, if ClamAV is installed, a ClamAV result. From there you can **Quarantine** it (restorable) or **Reveal in Finder**. It only says *Worth a closer look* when an executable, script or installer downloaded from the Internet also has a risk sign (unsigned, not notarized, rejected by Gatekeeper), and *dangerous* for a broken signature or a ClamAV match, so apps you built yourself are not flagged. Everything runs on your Mac; nothing is uploaded. Big apps such as a browser can take half a minute.
- **Battery of Bluetooth accessories.** The *Devices* tile of the menu bar popover (and its detail panel) now shows the battery of devices that macOS reports as a power source but `system_profiler` does not, for example Logitech mice and keyboards. A device that offers no battery still shows only its name.
- **The About window follows your language.** Its description had no translation and always appeared in Vietnamese. A new test now fails when any text in the app has no translation.

# Vutidy 0.8.0

Release date: 2026-11-20 · Platform: macOS 13 or later (only tried on Apple Silicon and one Intel Mac) · Status: **pre-release**. The [known issues of 0.1.0](#vutidy-010) still apply.

## What's new in 0.8.0

- **A warning when the Trash gets full.** When the Trash (and the Trash of external drives) goes over 5 GB, Vutidy sends a macOS notification and shows a toast with a button to empty it; the menu bar carousel gets a *Trash* card too. It measures every 10 minutes and warns at most once every 3 days, unless the Trash grew by half since the last warning. It only warns and never deletes by itself. macOS asks once whether Vutidy may send notifications, and measuring the Trash needs Full Disk Access. Switch the warning off in *Settings → Cleanup → Warn when the Trash is full*.

# Vutidy 0.7.0

Release date: 2026-11-19 · Platform: macOS 13 or later (only tried on Apple Silicon and one Intel Mac) · Status: **pre-release**. The [known issues of 0.1.0](#vutidy-010) still apply.

## What's new in 0.7.0

- **App updates check themselves.** *Updater* looks at your Homebrew casks in the background every 24 hours and tells you when something new shows up, with a button that opens the page. It never installs by itself. Switch it off in *Settings → General*; the page also shows when it last checked.
- **Real-time alerts can be acted on.** On *Protection*, each alert has **Quarantine**, **Show in Finder** and **Dismiss**. The menu bar card opens the page that actually lists the alerts. Alerts and the "last scanned" line disappear on their own when the file is gone.
- **Sensitive permissions can be revoked.** *Malware Removal → Sensitive permissions* has a **Revoke** button per app (it runs `tccutil reset`). Apps that are already uninstalled are no longer listed or flagged: macOS keeps their record but shows no way to delete it, and it cannot be used.
- **Files you pick yourself can leave Desktop and Documents.** In Space Lens, Large & Old Files and Duplicates, the files you tick are moved to the Quarantine (a permanent delete there goes to the Trash instead). Cleanup rules, the two folders themselves and every other protected area stay blocked. The message for a blocked item now says why in plain words.
- **Malware: Apple XProtect and optional ClamAV.** Vutidy reads what macOS XProtect and its background scan recorded. If you want a second opinion it can install ClamAV with one click (Homebrew), refresh the signature database when it is a day old and scan Downloads, Desktop, Applications and the launch folders.
- **Applications → Extensions.** A new page to review and remove third-party plug-ins and app extensions. The Uninstaller now also cleans extension data.
- **Mail Attachments and Photo Junk** are separate cleanup pages.
- **New sidebar header.** A glass tile with the logo next to the traffic lights replaces the black square.
- **Menu bar popover.** Compact metric tiles with a clearer number and unit, detail panels for CPU, Battery, Network and Devices, *Free Up* (Disk, Memory) and *Speed test* back on the tiles, a new footer with a settings menu, and the CPU temperature on the value row. The popover now closes only when you click outside it.
- **AI Advisor finds your tools when the app is opened from Finder** (Claude Code, Codex, Antigravity, Gemini CLI).
- **Full Disk Access:** Vutidy no longer shows its own restart prompts, macOS already asks to quit and reopen.
- **Text size is Small by default.** Until you pick another size in *Settings → Appearance → Text size*; a size you already chose is kept. The old *Default* step is now called *Medium*.
- **Recommendations carousel in the menu bar popover.** Swipe sideways through cards, each with one thing worth doing next and a button: free purgeable space, memory pressure, low disk, Dev Junk, app updates, apps you have not opened for 90 days, a Smart Scan when the last one is over a day old, and a review of which apps can reach sensitive data. Urgent cards get a highlighted button; **✕** hides a card for 7 days (it comes back if things get much worse). On a short screen the popover stops at the screen height and scrolls.

# Vutidy 0.6.0

Release date: 2026-11-17 · Platform: macOS 13 or later (only tried on Apple Silicon and one Intel Mac) · Status: **pre-release**. The [known issues of 0.1.0](#vutidy-010) still apply.

## What's new in 0.6.0

- **AI malware analysis (optional, off by default).** With the AI Advisor on, **Analyze with AI** on the Malware page asks the AI you chose (the same tools or API key as the advisor) to judge each finding as malicious, suspicious or likely benign and to suggest one action: quarantine, switch off, ignore or leave. Only anonymized descriptions are sent (your home folder and user name are hidden; no file contents), and **Show data sent** lists them. The AI cannot run anything: you confirm every action, the quarantine for all flagged items included, and files go to the Quarantine for 7 days. See the [security policy](SECURITY.md).
- **Real-time monitor is on by default.** It starts when the app opens and watches new files in Downloads, Desktop, Applications and the launch folders (it detects after a file is written and cannot block it). Switch it off with the *Real-time* tile or in *Settings*; a choice you already made is kept.
- **Protection card in the menu bar popover.** It shows whether the real-time monitor is on, the last file it checked, when the last malware check ran, and a **Check Now** button. A check or an alert that needs a look turns it amber.

# Vutidy 0.5.0

Release date: 2026-11-17 · Platform: macOS 13 or later (only tried on Apple Silicon and one Intel Mac) · Status: **pre-release**. The [known issues of 0.1.0](#vutidy-010) still apply.

## What's new in 0.5.0

- **Free Up from the menu bar.** The **Disk** and **Memory** tiles of the popover have a **Free Up** button that opens a detail panel beside the popover. Memory: Active, Wired and Compressed, pressure, swap, the five apps using most RAM (each with *Quit*) and a button to clear the memory cache. Disk: what fills the drive (Audio, Applications, Images, Documents, Movies and Other, estimated from your standard folders), drive health (SMART), Purgeable, the Trash, and buttons to open System Junk and Space Lens.
- **Turbo Boost switch in the popover (Intel Macs).** A toggle tile next to *Real-time* turns Turbo Boost off and on. It uses `DisableTurboBoost.kext` if you installed Turbo Boost Switcher (the kext is also found in `/Applications/tbswitcher_resources`), otherwise Low Power Mode. The kext still needs Reduced Security; Vutidy does not ship it.
- **CPU temperature on Intel Macs**, read from the core sensors through the SMC (it was missing, only a word such as *Warm* showed).
- **Devices tile.** One compact line per device. A paired iPhone, iPad or Apple Watch that is nearby is listed too, without a battery level (macOS offers no public way to read it).
- **Popover layout.** *Speed test* moved to the bottom right of the Network tile like *Free Up*, and *Real-time* and *Turbo Boost* became two toggle tiles side by side.
- **English is the default language** until you choose another one in *Settings* (it no longer follows the system language by itself). Your saved choice is kept.
- **Fix: Uninstaller.** The detail panel with the *Remove* button no longer scrolls out of view when the app list is long. The list scrolls on its own and the panel stays in place.
- **AI Advisor (optional, off by default).** After a scan, an AI ranks what is worth doing and each step is a button. It uses the AI tools already signed in on your Mac (Claude Code, Codex, Antigravity, Gemini CLI, no API key) or the Claude API with your key, with a model picker per source. It can ask to look deeper into big groups such as Docker (read-only, anonymized details). The AI only picks from actions Vutidy offers; cleaning goes to the Quarantine, and steps that run a tool's own command are labelled *Can't be undone* and confirmed one by one. **Turning it on sends scan totals (and, if the AI asks, anonymized item details) to the AI service of the source you pick**; see the [security policy](SECURITY.md).
- **Malware page: Apple's XProtect results, and optional ClamAV.** Vutidy now reads the XProtect database version and the latest run of Apple's Remediator modules from the system log (local, nothing is sent) and reports anything other than "no threat detected". If you install ClamAV (`brew install clamav`), **Scan with ClamAV** downloads its public signature database once and scans Downloads, Desktop, Applications and LaunchAgents/Daemons; matches can be quarantined like other findings. Not yet tried against a real detection or a real ClamAV install.
- **Running AI agents.** Smart Scan lists Claude Code, Codex, MCP servers and similar processes, nests sub-agents under their parent and flags orphaned or runaway ones, which you can end after a confirmation.
- **Close apps to clean their cache.** Running browsers and a few chat and music apps are quit politely (never forced), cleaned, then reopened. Automatic cleaning never closes apps.
- **Fix: Docker sizes.** The "safe" Docker image size came from unused *tagged* images, but the command only removes *dangling* ones, so cleaning could free almost nothing. Dangling images are now the safe item; unused tagged images are a **Review** item with a warning.
- **Popover cards open the matching page**, the maximized Settings window buttons work, and the Performance card no longer overflows.

# Vutidy 0.4.0

Release date: 2026-11-17 · Platform: macOS 13 or later (only tried on Apple Silicon) · Status: **pre-release**. The [known issues of 0.1.0](#vutidy-010) still apply.

## What's new in 0.4.0

- **A new Smart Scan screen.** One layout for every state (not scanned, scanning, cleaning, done): a hero card, a disk card and five fanned cards, one per group. After a scan each card shows its own result (for example *8.19 GB safe to clean*) and opens the right page. The disk card shows what you would have free after cleaning. **Scan and clean now** is a button next to **Start Smart Scan**.
- **Clean automatically after a scan** (off by default, *Settings → Cleanup*). Only Safe items that can be undone are taken, and files go to the Quarantine. Items cleaned with a command (Docker, Go, Homebrew), the Trash and anything marked *Review* are never cleaned for you.
- **A new icon set.** The main pages use the stroke icons of the new design, and the sidebar tiles take the colour of their group.
- **Optimization has two tabs**, *Performance* and *Startup*. Performance gains a temperature gauge. In *Startup*, login items and launch items are **grouped by vendor** (Apple collapsed), so a long list is easy to scan.
- **Cooling for Intel Macs.** A card on *Optimization → Performance* (shown on Intel only) turns on **Low Power Mode** (`pmset`, asks for your password) and, if you already installed Turbo Boost Switcher's `DisableTurboBoost.kext`, loads or unloads it. Vutidy does not ship that kernel extension, and it needs Reduced Security. **Not tried on an Intel Mac yet.**
- **Malware page: act on what it finds.** Each finding can be **quarantined** (restorable for 7 days; a launch item is switched off first), **switched off** or **ignored**. Later scans mark what is **new** and keep ignored items hidden.
- **More checks in the malware scan:** apps holding sensitive permissions (Full Disk Access, Accessibility, Screen Recording, Input Monitoring; needs Full Disk Access to read), third-party configuration profiles, browser extensions that run on every site with sensitive permissions, system extensions, `DYLD_*` variables in launchd plists, a proxy that points off this Mac, `/etc/hosts` redirects, SSH keys allowed to log in, hidden programs in your home folder and unsigned programs in *Application Support*. A tiny list of published indicators is built in; you can add your own in `malware-ioc.json`. Vutidy is still **not an antivirus**.
- **Fixes.** The menu bar popover background reaches under the top edge, so no mismatched band shows above the header. The fanned cards no longer flicker when the pointer crosses from one card to its neighbour.

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
