# Security policy

Vutidy removes files from your Mac, so safety bugs matter. Thank you for taking the time to report one.

## Contents

- [Supported versions](#supported-versions)
- [Reporting a vulnerability](#reporting-a-vulnerability)
- [What Vutidy protects](#what-vutidy-protects)
- [What it does not protect](#what-it-does-not-protect)
- [Scope](#scope)

## Supported versions

Vutidy is a pre-release. Only the latest version gets fixes; check that a problem still exists in the newest build before you report it.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.** Use the repository host's private reporting (on GitHub: the *Security* tab → *Report a vulnerability*), or contact the maintainer privately through the channel listed on the project page. Include what you found and what it allows, the version and macOS version, and steps to reproduce.

**Never include real private keys, passwords or personal files** in a report; use throw-away data.

This is maintained in spare time, so these are goals, not guarantees: an acknowledgement within 7 days, an assessment within 14, and a fix in the next release for a confirmed problem. Please keep details private until a fix is out.

## What Vutidy protects

- **Your files from Vutidy's own mistakes.** A hard blocklist (`/System`, `/usr`, keychains, `~/Documents`, `~/Desktop`, `~/.ssh`, `~/.gnupg`, the Photos library originals and more, including `..` paths and symlinks into them) overrides every rule and every selection.
- **Reversibility.** The default mode moves items to a Quarantine that restores to the exact original path (and refuses to overwrite). Every action, dry runs included, is written to a local audit log.
- **No surprises.** Scanning never changes anything; only safe items are preselected; the commands that will run are shown first.
- **Your privacy.** No telemetry, no account, no network use except what you trigger (the speed test, a Homebrew update check, a check for a new Vutidy version on GitHub that sends no information about your Mac, opening the donation link in your browser). Nothing from your Mac is uploaded.
- **Least privilege.** There is no background root helper. Administrator tasks use the standard macOS password dialog each time, and Vutidy never stores or sees the password.

## What it does not protect

- **It is not an antivirus.** The persistence scanner and the real-time monitor point out unfamiliar launch items and new executables; they cannot block anything and detect only after a file is written.
- **You can still choose to delete something important** in a *Review* item, in Large & Old Files or with *Delete permanently*. Read before you clean.
- **Command-based cleanups** (`docker prune`, `go clean`, `brew cleanup`) and the Trash page cannot be undone.
- **The Quarantine is not encrypted** and sits on the same disk; anyone with access to your account can read it. It is not a backup.
- **Builds are signed ad hoc** and are not notarized. Build from source you trust.
- **The audit log is plain text** and records file paths.

## Scope

In scope: this repository and the Vutidy app, for example the blocklist and path handling (traversal, symlinks), the Quarantine (restore location, overwriting, permissions), the command runner (argument handling for tools it invokes), the rule loader (a malicious user rule that escapes the blocklist), the real-time monitor, and any way to make Vutidy remove something it should not.

Out of scope: weaknesses of macOS itself, other apps, and attacks that need you to already be running malicious code as your user (such code does not need Vutidy to delete your files).
