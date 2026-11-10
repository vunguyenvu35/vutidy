# Plan: stronger malware checks and startup control

Status: **in progress**. Part B (see what opens at login) is built; Part A (malware checks) is planned. Update this page as items are done.

## Contents

- [Goals and non-goals](#goals-and-non-goals)
- [Part A: malware checks](#part-a-malware-checks)
- [Part B: apps that open at login](#part-b-apps-that-open-at-login)
- [Rules for every new check](#rules-for-every-new-check)
- [Order of work](#order-of-work)

## Goals and non-goals

**Goals**

- Find more of what matters on a Mac: things that start by themselves, unsigned or tampered programs, and signs that Gatekeeper was bypassed.
- Tell the user *what opens at login* and let them control it.
- Keep false alarms low, so a red warning is worth reading.

**Non-goals**

- Vutidy stays **not an antivirus**: no real-time blocking, no malware signature database of its own. Say so wherever results are shown.
- No server and no upload. Everything is read on the Mac.

## Part A: malware checks

What exists today ([`MalwareCheck.swift`](../../Sources/Modules/MalwareCheck.swift), [`Protection.swift`](../../Sources/Modules/Protection.swift)): security posture (SIP, Gatekeeper, XProtect, FileVault, Firewall), up to 150 apps checked for signature and notarization, launch agents and daemons (odd locations, Apple impersonation, download-and-run commands, unsigned), shell profiles and cron, and an FSEvents monitor that reports after a file is written.

### Phase 1: cheap and valuable (no infrastructure)

| # | Item | How | Notes |
| --- | --- | --- | --- |
| A1 | **Use Apple's XProtect rules** | Read the YARA rules of the installed `XProtect.bundle` and run them on new apps and downloads; show the XProtect version | Best sample quality without keeping a database. Needs a YARA reader; start with name and hash lists if a full engine is too much |
| A2 | **More persistence points** | Login Items and background items (Part B), configuration profiles (`profiles list`), browser extensions, system and kernel extensions, `emond`, `at` jobs, folder actions, `DYLD_INSERT_LIBRARIES` and `EnvironmentVariables` in launchd plists | Login Items and background items are the most used persistence on current macOS |
| A3 | **Quarantine and origin** | Read `com.apple.quarantine` and `kMDItemWhereFroms` of new executables | An executable in Downloads with no quarantine flag is a signal |
| A4 | **Entitlements and hardened runtime** | Flag `disable-library-validation`, `allow-dyld-environment-variables`, `get-task-allow` on apps that have no reason for them | Low severity alone; useful in a score |
| A5 | **Gatekeeper bypass** | Look for `xattr -d com.apple.quarantine` and `spctl --master-disable` in autostart places | |

### Phase 2: design needed

| # | Item | Why |
| --- | --- | --- |
| A6 | **Baseline and "new since last scan"** | Store the launch items, login items and apps seen last time; report what is new. Fewer false alarms and a real change signal |
| A7 | **Score instead of hard classes** | Combine signals: unsigned **and** in `/tmp` **and** runs at login **and** `curl | sh` is far worse than one signal |
| A8 | **Allowlist** | Let the user mark "I know this item" so it is not reported again. Many developer tools are unsigned. Ship together with A6 |
| A9 | **Running processes** | List unsigned processes that talk to the network or run from a temporary folder (read only: `lsof`, `nettop`) |

### Phase 3: only with a clear need

| # | Item | Cost |
| --- | --- | --- |
| A10 | **Endpoint Security** to block instead of report | Needs a Developer ID, a system extension and Apple's entitlement. This turns Vutidy into a different product |
| A11 | **Own hash / IOC database** from public feeds | Needs an update service, false-positive handling and some responsibility when a clean file is flagged |
| A12 | **YARA rules of our own** | Maintenance burden |

**Not planned:** A10 to A12 until Vutidy is signed and has real users.

## Part B: apps that open at login

### The need

Know which apps start when macOS starts, and be able to turn them off.

### What macOS offers (and does not)

| Kind | Where it lives | Can Vutidy list it | Can Vutidy switch it |
| --- | --- | --- | --- |
| **Launch agents and daemons** (plists in `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`) | launchd | yes (already in *Optimization → Startup items*) | **yes**: `launchctl bootout` + `disable`; admin password for `/Library` |
| **Login Items and background items** (System Settings → General → Login Items, apps that register with `SMAppService`) | Background Task Management (BTM) | **yes** (new card *Opens at login*) | **no public API.** Only the user can change them in System Settings, so each row opens that page |
| **Legacy login items** (the older "Open at Login" list) | System Events | possible with AppleScript | possible (`delete login item`, `make login item`), but it asks for **Automation** permission, so not enabled yet |

### Built

- [`LoginItems.swift`](../../Sources/Modules/LoginItems.swift): reads the user's BTM store and returns each app or helper with name, developer, path, **on/off**, and whether the file is **missing** (deleted, in the Trash or in a Gatekeeper temp folder).
- [`LoginItemsCard.swift`](../../Sources/Vutidy/LoginItemsCard.swift): the card *Opens at login* in *Optimization*, with filters *On / Disabled / File missing / All* and a **Manage** button per row that opens *System Settings → Login Items*.
- `vutidy-cli startup` prints the same list.

### Decision: do not use `sfltool dumpbtm`

`sfltool dumpbtm` works but asks for **administrator access** ("Allow administrator access for sfltool?"), so a card that loads on its own would pop a password dialog every time. Vutidy reads the BTM file of the current user instead:

- `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v<N>-<GeneratedUID>.btm` is readable by everyone; the right file is picked by the user's `GeneratedUID` (`dscl . -read /Users/<name> GeneratedUID`).
- It is an `NSKeyedArchiver` file. `plutil -convert xml1` turns it into XML; Vutidy walks `$objects` by hand (type `0x2` = app, `0x4` = login item; `disposition & 1` = enabled).
- The format is private and has changed between macOS versions (`v8`, `v9`, `v16`, `v18`). If the file cannot be read or understood, the card shows an empty list and nothing else breaks. **Re-check on each new macOS release.**

### Next

| # | Item | Notes |
| --- | --- | --- |
| B1 | **Real switch for legacy login items** through AppleScript | Explain the Automation prompt first; do it only when the user presses *Allow Vutidy to manage login items* |
| B2 | **Count login items in the *Startup items* gauge** | Today it counts launch agents and daemons only |
| B3 | **Notify when a new login item appears** | Needs A6 (baseline). Also useful as a malware signal |
| B4 | **One list** that merges launch agents, daemons and login items, sorted by how likely each is to be unwanted (missing file, unsigned, new) | |
| B5 | Unit tests with a small saved BTM file | The format check above needs a fixture |

## Rules for every new check

1. **Name what it saw and why it matters** in one sentence, with the path. No bare "suspicious".
2. **Severity** high only when the evidence is strong on its own; weak signals are *low* and may be combined (A7).
3. **Test it on a real, lived-in Mac** (developer tools, Homebrew, JetBrains) before shipping, to count false alarms.
4. **Never ask for a password or a permission on its own.** Anything that needs one starts from a button and says why.
5. **Never block or delete automatically.** The user decides; destructive actions go through the safety layer and the audit log.
6. **Update the user guide** ([Protection](../user-guide/04-protection.md), [Speed](../user-guide/05-speed.md)) and the limits section in the same change, so the app does not promise more than the check does.

## Order of work

1. B1 and B2 (finish startup control).
2. A2 (more persistence points, reusing Part B) then A6 and A8 (baseline and allowlist, together).
3. A1 (XProtect rules), A3, A4, A5.
4. A7 (score) and A9.
5. Revisit A10 to A12 only once releases are signed with a Developer ID and there is demand.
