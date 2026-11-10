# Clean architecture

How Vutidy's code is divided, what may depend on what, and how one clean operation travels from a button to the disk.

## Contents

- [The targets](#the-targets)
- [The dependency rule](#the-dependency-rule)
- [How a clean operation flows](#how-a-clean-operation-flows)
- [Rules are data](#rules-are-data)
- [Localization](#localization)
- [Concurrency and testing](#concurrency-and-testing)
- [Decisions](#decisions)

## The targets

Swift Package Manager (`Package.swift`) defines these targets, from the inside out:

| Target | Responsibility | Depends on |
| --- | --- | --- |
| `CoreKit` | Shared models (`ScanItem`, `SafetyLevel`, `CleanMode`, `CleanReport`), `ByteFormat`, `AppPaths`, `ProcessRunner`, and the localization (`L10n`, `tr`, `trf`, the translation tables) | nothing |
| `SafetyLayer` | `Blocklist`, `Quarantine` (move, restore, expire), `AuditLog`, `ActionExecutor` (the single entry for removals) | `CoreKit` |
| `ScanEngine` | `FileWalker` (allocated size, hard links, no symlinks), `Glob`, `DirectoryTree` (for Space Lens), bounded `Concurrent.map` | `CoreKit` |
| `RuleEngine` | `Rule`, `RuleLoader` (bundled + user JSON), `RuleEvaluator` (matches, excludes, age, running-app checks) and `rules.json` | `CoreKit`, `ScanEngine`, `SafetyLayer` |
| `Modules` | Every feature: `CleanerModule` implementations (System Junk, Dev Junk, Trash…), Docker/JetBrains/project detectors, Uninstaller, Duplicates, Large & Old, Optimization, Maintenance, Protection (persistence + real-time), Recommendations, SystemMonitor, Smart Scan, speed test, Updater, Cloud Cleanup | all of the above |
| `Vutidy` | The SwiftUI app: `AppState`, views, design system, shortcuts, settings | `Modules` |
| `vutidy-cli` | The command line front end | `Modules` |

`Tests/VutidyTests` (swift-testing) can see every library target.

## The dependency rule

Source dependencies point **inward** only: the UI and CLI know the modules; modules know the engines; engines know the core; the core knows nothing. Concretely:

- No module or engine imports SwiftUI. The scanners return plain `ScanItem` values and run the same under the CLI and the app.
- `SafetyLayer` does not know about rules or modules. It receives `ScanItem`s and applies the blocklist, the mode and the audit log.
- The UI never deletes a file itself; it calls `ActionExecutor`.
- Anything the UI needs from a module is a plain function or value (`Maintenance.tasks`, `Optimization.launchItems()`).

## How a clean operation flows

```
 Button "Clean 2.6 GB"  (CleanupView action bar)
        │  mode + selected ScanItems
        ▼
 AppState.clean(id, mode)
        │
        ▼
 ActionExecutor.clean  ── only items with selected == true
        │ for each item:
        ├─ item has a command?  ── dry run → note "$ cmd"   else ProcessRunner.run(cmd)
        ├─ Blocklist.reason(for: url)  → skipped("blocked: …")
        ├─ file still exists?          → skipped("no longer exists")
        └─ mode:  dryRun | moveToTrash | quarantine | permanent
        ▼
 AuditLog.append(...)   (every outcome, dry runs included)
        ▼
 CleanReport  →  toast, results list updated, Quarantine refreshed
```

The scan side is the mirror image: `CleanerModule.scan` → `RuleEvaluator` (globs, excludes, age, running apps, blocklist, sizes) → `[ScanItem]`.

## Rules are data

Most cleanup knowledge is in `Sources/RuleEngine/Resources/rules.json`: paths, excludes, safety level, optional native command, "requires" tool, minimum age. Logic that cannot be a glob (Docker's `system df`, JetBrains version comparison, stale project folders, broken plists) is a small detector in `Modules`. Users can add or override rules with JSON files in `~/Library/Application Support/Vutidy/Rules/`.

## Localization

Strings are looked up with `tr("…")` and `trf("… %@", args)`. The key is the Vietnamese source sentence; `vi` returns it unchanged; `en`, `ja`, `zh` come from dictionaries in `CoreKit/Localization`, falling back to English, then the key. The app rebuilds its view tree when the language changes. A test checks coverage and placeholders.

## Concurrency and testing

Scanning uses `async` functions and a bounded task group (`Concurrent.map`) so disk I/O is not saturated. UI state lives in one `@MainActor AppState`. Pure logic is covered by unit tests on fixture directories in a temp folder; the safety layer (blocklist, quarantine, executor modes) has the densest tests. Anything needing root or the GUI is on the manual [test plan](../development/test-plan.md).

## Decisions

| Decision | Why |
| --- | --- |
| One `Modules` target instead of one per feature | Faster builds and simpler imports; features share detectors and helpers. Split later if a feature grows a dependency. |
| One removal entry point | A single place to apply the blocklist, modes and audit log; impossible to forget a check |
| Keys are source sentences, not identifiers | Existing code stays readable; a test, not a naming convention, guarantees completeness |
| Rules as JSON data | Updatable without a release, no parser dependency |
| `@ViewState` instead of `@State` | The SwiftUI macro plugin behind `@State` ships only with Xcode; the wrapper builds with Command Line Tools too |
| No privileged helper yet | Requires a signed daemon; the macOS password prompt covers the few admin tasks |
