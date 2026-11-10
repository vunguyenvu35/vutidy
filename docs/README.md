<p align="center"><img src="assets/brand/logo-mark-256.png" alt="Vutidy" width="88"></p>

# Vutidy documentation

Pick the part that matches what you want to do.

## Using Vutidy

| Document | Read it to |
| --- | --- |
| [Installing on macOS](getting-started/install-macos.md) | Build and open Vutidy, and grant Full Disk Access |
| [User guide](user-guide/README.md) | Learn every screen and feature, chapter by chapter |
| [Release notes](../RELEASE_NOTES.md) | See what is in each version and what is not yet verified |
| [Security policy](../SECURITY.md) | Read what Vutidy protects and what it does not, and how to report a vulnerability |

The user guide chapters: [Getting started](user-guide/01-getting-started.md) · [Smart Scan](user-guide/02-smart-scan.md) · [Cleanup](user-guide/03-cleanup.md) · [Protection](user-guide/04-protection.md) · [Speed](user-guide/05-speed.md) · [Applications](user-guide/06-applications.md) · [Files](user-guide/07-files.md) · [Quarantine and safety](user-guide/08-quarantine-and-safety.md) · [Menu bar](user-guide/09-menu-bar.md) · [Settings](user-guide/10-settings.md) · [Shortcuts](user-guide/11-shortcuts.md) · [Languages](user-guide/12-languages.md) · [Command line](user-guide/13-cli.md) · [Support Vutidy](user-guide/14-support.md) · [Troubleshooting](user-guide/15-troubleshooting.md)

## How it is built

| Document | Read it to |
| --- | --- |
| [Clean architecture](design/clean-architecture.md) | Understand the targets, the dependency rule and how a clean operation flows |
| [Architecture (original design)](design/architecture.md) | Read the first plan, kept as written, plus what changed when it was built |
| [Design spec](design/design-spec.md) | See the Graphite Glass tokens, layout, screens and components |

Machine-readable design tokens live in [design/tokens](design/tokens) (`tokens.json`, `tokens.css`, `Theme.swift`), and the canvas sources of the first mock-ups in [design/source](design/source).

## Contributing

| Document | Read it to |
| --- | --- |
| [Development guide](development/development.md) | Build, test, package, add a rule, add a language, regenerate the brand assets |
| [Releasing](development/release.md) | Publish a version with GitHub Actions: tag, build, sign, notarize, checksums |
| [Test plan](development/test-plan.md) | Run the manual checklist on a real Mac |

## Images and brand

Logos, the palette and the app icon are in [assets/brand](assets/brand/README.md). The donation QR codes are in [assets/donate](assets/donate). `scripts/check-doc-links.sh` lists links and images that no longer point anywhere.
