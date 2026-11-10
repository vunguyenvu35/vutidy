# Smart Scan

One scan that looks at everything at once. Open it from the sidebar or with **⌘1**.

## Contents

- [What it scans](#what-it-scans)
- [The result screen](#the-result-screen)
- [Cleaning](#cleaning)
- [Limits](#limits)

## What it scans


![Smart Scan before scanning](../assets/screens/smart-scan-start.webp)

*Before the first scan: the ring shows your free disk space and **Start scanning** begins the scan. The three cards stay at zero until it finishes.*

Smart Scan runs these in parallel:

| Part | Detail |
| --- | --- |
| System Junk | Caches, logs, crash reports, broken preferences, Mail downloads, the Photos cache ([Cleanup](03-cleanup.md#system-junk)) |
| Dev Junk | Docker, JetBrains, Node, Go, Xcode, Homebrew… and the project folders you chose ([Cleanup](03-cleanup.md#dev-junk)) |
| Trash | Your Trash and the Trash of external drives |
| Persistence | Launch agents and daemons with their code-signature state ([Protection](04-protection.md)) |
| Speed | Launch items and the processes using the most CPU ([Speed](05-speed.md)) |

The results are also handed to the individual pages, so opening *System Junk* afterwards shows the same items without scanning again.

## The result screen


![Smart Scan result with the Clean and Preview buttons](../assets/screens/smart-scan-result.webp)

*After a scan: the headline says how much space you can get back, and the three cards show where it comes from.*

- **Header.** When it was scanned and the headline: *Your Mac can get back X*.
- **Hero.** A ring of your disk (used, purgeable, free) with the current free space in the middle and, once there is something to clean, what it would be after cleaning. At the right: **Clean**, **Preview (dry-run)** and a reminder that it can be undone for 7 days.
- **Three cards.**
  - *Cleanup*: the safe size of System Junk, Dev Junk and Trash, and the size that needs review.
  - *Protection*: how many launch items were found, how many are unsigned or missing a program, and the real-time alerts.
  - *Speed*: user launch agents, available memory and a CPU sparkline.
  Each card has an arrow that opens its page.

If nothing is found the hero says **Your Mac is tidy** and shows no Clean button.

## Cleaning

**Clean** only takes the items marked **Safe**. It asks once:

- Safe files go to the **Quarantine** (restorable for 7 days by default).
- Items already in the Trash are deleted for good (they were already thrown away) and items cleaned through a tool's own command (`docker prune`, `go clean`, `brew cleanup`) cannot be restored. The confirmation says so.

**Preview (dry-run)** performs exactly the same steps without changing anything and shows the size it would free.

Afterwards a toast shows how much was moved, with an **Undo** link that opens the Quarantine.

## Limits

- The sizes are *allocated* sizes. APFS clones and purgeable space make the real gain differ a little, so the numbers are estimates.
- Smart Scan does not run the heavier modules (Duplicates, Large & Old Files, Space Lens, Cloud Cleanup, Uninstaller). Open those pages when you want them.
- It does not run on a schedule yet.
