# Getting started

From install to your first safe clean in five steps.

## Contents

- [Your first scan in five steps](#your-first-scan-in-five-steps)
- [The main window](#the-main-window)
- [Full Disk Access](#full-disk-access)
- [What is selected by default](#what-is-selected-by-default)
- [Where to go next](#where-to-go-next)

## Your first scan in five steps

1. **Install.** Follow [Installing on macOS](../getting-started/install-macos.md) and open `dist/Vutidy.app`.
2. **Grant Full Disk Access** (optional but recommended, see [below](#full-disk-access)).
3. **Open Smart Scan** (⌘1) and press **Start scanning**. Nothing is changed by scanning.
4. **Read the result.** The big number is what Vutidy thinks it can give back. Open the cards (Cleanup, Protection, Speed) to see where it comes from.
5. **Preview, then clean.** Press **Preview (dry-run)** to see exactly what would happen. When you are happy, press **Clean** and choose *Move to Quarantine*. You can undo for 7 days (see [Quarantine and safety](08-quarantine-and-safety.md)).

**Step 3: press Start scanning.** Smart Scan is the first page in the sidebar. Press the purple button and wait; scanning only reads.

![Smart Scan before the first scan](../assets/screens/smart-scan-start.webp)

**Steps 4 and 5: read the result, then preview and clean.** The headline says how much you can get back. **Preview (dry-run)** shows what would happen without changing anything; **Clean** moves the Safe items to the Quarantine.

![Smart Scan result with Clean and Preview buttons](../assets/screens/smart-scan-result.webp)

> **Tip.** Press **⌘K** at any time to search every feature by name, and hover a sidebar item to see its shortcut.

## The main window

![The Vutidy main window on Smart Scan before the first scan](../assets/screens/smart-scan-start.webp)

*The main window on Smart Scan: sidebar on the left, the page on the right.*

What you see in the screenshot:

- **Sidebar.** A search field (**⌘K**) and every feature, grouped as Cleanup, Protection, Speed, Applications and Files. Each page has its own colour. Point at an item to see its keyboard shortcut. The **Quarantine** card at the bottom is always visible: it shows how much is waiting there and opens the list.
- **Bottom of the sidebar.** The **language** menu, the **Real-time** indicator (the monitor of new files, see [Protection](04-protection.md#real-time-monitor)), and the gear that opens [Settings](10-settings.md) (⌘,).
- **Page.** A header with the page name, then its content. The cleanup pages pin an **action bar** to the bottom of the window with the selected size and the Clean button.
- **Menu bar icon.** A small popover with the state of your Mac and recommendations; see [Menu bar](09-menu-bar.md).

## Full Disk Access

macOS protects some folders (Mail downloads, the Photos cache, the Safari cache, parts of iCloud Drive). Without **Full Disk Access** Vutidy skips them and a banner on Smart Scan, System Junk, Privacy and Cloud Cleanup says so. You can dismiss the banner with **×**.

Press **Grant access…** in the banner (or in *Settings → Protection*). Vutidy opens *System Settings → Privacy & Security → Full Disk Access* and shows a small panel next to it:

![The Full Disk Access guide panel](../assets/screens/fda-guide.webp)

*The guide panel. It stays on top of System Settings while you work.*

1. In the System Settings list, **turn on the switch for Vutidy**.
2. If Vutidy is not in the list, **drag the icon from the panel** into it.
3. Enter your password or use Touch ID if macOS asks.

Vutidy notices the moment the permission is on and the panel says **Access granted!**; press **Restart Vutidy** so macOS applies it to the whole app. If it still says the permission is missing, or the list has several Vutidy entries, use **Reset permission** in the panel (or in *Settings → Protection*): it removes Vutidy from the list so you can grant it cleanly. See [Troubleshooting](15-troubleshooting.md#the-banner-stays-after-i-turned-full-disk-access-on).

Vutidy has to run as a real app for this: a bare `swift run Vutidy` has no bundle ID or icon, so the guide tells you to open `dist/Vutidy.app` instead (build it with `scripts/make-app.sh`). Step by step in [Installing on macOS](../getting-started/install-macos.md#grant-full-disk-access).

## What is selected by default

Every item has a **safety level**:

| Level | Meaning | Selected by default |
| --- | --- | --- |
| **Safe** | Regenerated automatically (caches, logs, build products). | Yes |
| **Review** | Probably fine, but you should look: old IDE configuration, language models, an Xcode archive, large files. | No |
| **Dangerous** | Reserved for items that need an explicit, separate confirmation. | No |

Smart Scan's **Clean** button only ever touches *Safe* items. Anything marked *Review* has to be selected by you, by hand.

## Where to go next

- [Smart Scan](02-smart-scan.md) for the one-button scan.
- [Cleanup](03-cleanup.md) to understand the pages and the clean modes.
- [Quarantine and safety](08-quarantine-and-safety.md) before you clean anything you care about.
