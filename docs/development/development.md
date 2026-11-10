# Development guide

Build, test, package and extend Vutidy.

## Contents

- [Requirements](#requirements)
- [Build and run](#build-and-run)
- [Command Line Tools vs Xcode](#command-line-tools-vs-xcode)
- [Tests](#tests)
- [Project layout](#project-layout)
- [Add a cleaning rule](#add-a-cleaning-rule)
- [Add a module or a page](#add-a-module-or-a-page)
- [Add or change a translation](#add-or-change-a-translation)
- [Add a shortcut action](#add-a-shortcut-action)
- [Packaging](#packaging)
- [Documentation screenshots](#documentation-screenshots)
- [Brand and icon](#brand-and-icon)
- [Conventions](#conventions)

## Requirements

- macOS 13 or later.
- Swift 5.9 or later (Xcode, or the Command Line Tools from `xcode-select --install`). The package builds in Swift 5 language mode.
- Optional: Node and a Playwright install, only to regenerate the logo PNGs.

## Build and run

```bash
swift build                      # debug build of everything
swift run Vutidy                 # the app
swift run vutidy-cli scan dev    # the command line tool
swift build -c release --product Vutidy
```

`swift run Vutidy` starts a bare executable. It sets the activation policy itself so a window appears, but it has no bundle ID and no icon; use `scripts/make-app.sh` when you need a real app (Full Disk Access, the Dock icon).

Set `VUTIDY_HOME=/some/temp/folder` to keep the Quarantine, audit log and rules out of your real data while developing, and `VUTIDY_LANG=ja` (or `zh`, `en`, `vi`) to start in a given language.

## Command Line Tools vs Xcode

The package builds with either, with two differences you will notice if you have only the Command Line Tools:

- **`@State` is a macro** in the newest SDK, and its plugin (`SwiftUIMacros`) ships only with Xcode. The views therefore use `@ViewState`, a small property wrapper in `Sources/Vutidy/Components.swift` built on `@StateObject`. It behaves like `@State`; keep using it. Other wrappers (`@StateObject`, `@EnvironmentObject`, `@FocusState`, `@Published`) are not macros and work as normal.
- **XCTest is not available**, so tests use **swift-testing** (`import Testing`).

## Tests

```bash
swift test
```

Tests live in `Tests/VutidyTests` and use swift-testing (`@Test`, `#expect`, `@Suite`). `Fixture.swift` builds fake directory trees in a temp folder.

| Area | Tests |
| --- | --- |
| Safety layer | Blocklist (system, user data, ancestors, `..`, symlink escape, relative paths), Quarantine (round trip, no overwrite, persistence, expiry), `ActionExecutor` (modes, blocked, missing, audit, command items) |
| Scan engine | Allocated size, hard links, symlinks, glob and braces, tree sorting and aggregation |
| Rule engine | Bundled rules decode with unique ids; excludes, empty results, safety defaults, age filter, running apps, blocklist, `requires` |
| Modules | Docker size and `df` parsing, JetBrains versions, stale projects, duplicates (including a difference in the middle of the file), Large & Old, uninstaller leftovers, recommendations and dismissal, system monitor sanity |
| Localization | Every key translated in `ja` and `zh`, placeholder counts match, fallbacks, formatted strings, system language resolution |

If the first `swift test` straight after a `swift build` fails with *external macro implementation type 'TestingMacros…' could not be found*, run it again; if it persists, delete `.build`.

When you add safety-relevant behaviour, add a test with it. The blocklist is meant to stay at full coverage.

## Project layout

```
Package.swift
Sources/
  CoreKit/        models, helpers, localization (Localization/)
  SafetyLayer/    Blocklist, Quarantine, AuditLog, ActionExecutor
  ScanEngine/     FileWalker, Glob, DirectoryTree, Concurrent
  RuleEngine/     Rule, RuleEvaluator, Resources/rules.json
  Modules/        one file per feature
  Vutidy/         the SwiftUI app (AppState, views, DesignSystem, Shortcuts, Settings)
  vutidy-cli/     main.swift
Tests/VutidyTests/
scripts/          make-app.sh, check-doc-links.sh
docs/             this documentation, design tokens, brand assets
```

See [Clean architecture](../design/clean-architecture.md) for the dependency rule.

## Add a cleaning rule

Edit `Sources/RuleEngine/Resources/rules.json` (bundled) or drop a `.json` file with an array of rules in `~/Library/Application Support/Vutidy/Rules/` (user rules; the same `id` overrides). A rule:

```json
{
  "id": "npm-cache",
  "module": "dev-junk",
  "title": "Cache npm",
  "group": "Node.js",
  "paths": ["~/.npm/_cacache"],
  "exclude": [],
  "minAgeDays": 0,
  "skipIfRunningBundle": "com.jetbrains.*",
  "appNotRunning": false,
  "safety": "safe",
  "command": ["go", "clean", "-cache"],
  "requires": "go",
  "detail": "Shown under the item"
}
```

| Field | Meaning |
| --- | --- |
| `id` | Unique, stable. Also decides the icon in `CategoryStyle` (prefix match) |
| `module` | `system-junk`, `dev-junk` or `privacy` |
| `title`, `group`, `detail` | Shown to the user; `group` is the category card. They are passed through `tr()`, so add translations for new text |
| `paths` | Globs (`~`, `*`, `?`, `{a,b}`); each match is one item |
| `exclude` | fnmatch patterns to skip |
| `minAgeDays` | Skip matches modified more recently than this |
| `skipIfRunningBundle` | Skip the whole rule while an app matching this bundle-ID glob is running |
| `appNotRunning` | Skip a match whose folder name equals the bundle ID of a running app |
| `safety` | `safe` (preselected), `review`, `dangerous` |
| `command` | Clean with this command instead of removing files (no undo); `paths` is then only used for the size |
| `requires` | Only offer the rule when this tool is installed |

Paths on the [blocklist](../user-guide/08-quarantine-and-safety.md#the-blocklist) are dropped no matter what. Add a test with a fixture tree for anything non-trivial.

## Add a module or a page

1. **Scanner.** Implement `CleanerModule` (`scan(progress:) async throws -> [ScanItem]`) in `Sources/Modules/`, or write plain functions for a page that is not a cleanup list.
2. **Never delete directly.** Return `ScanItem`s and let `ActionExecutor` remove them.
3. **Page.** Add a case to `Page` in `AppState.swift` (title, icon, group, `cleanupID` if it is a cleanup page), a colour in `DesignSystem.swift` (`Page.tint`), a view, and a case in `RootView.detail`.
4. **Shortcut.** Add the page to `ShortcutAction.pageCombos` in `Shortcuts.swift` with a default key.
5. Translate the new strings, add tests, and document it in the [user guide](../user-guide/README.md).

## Add or change a translation

Translations live in `Sources/CoreKit/Localization/`: `English.swift`, `Japanese.swift`, `Chinese.swift`. Each is a dictionary from the **Vietnamese source sentence** to the translation. Use `tr("source")` for plain text and `trf("source %@", arg1, …)` for text with values (placeholders are always `%@`; write a literal percent as `%%` in strings that take arguments).

To add or fix a string: use `tr()` or `trf()` in code, then add the same key to all three files. `swift test` fails if a key is missing in Japanese or Chinese, or if the `%@` count differs.

To add a language: add a case to `Language` in `L10n.swift` (name, locale, system-language prefix), add a `Translations` table with all keys, register it in `L10n.tables`, and extend the tests.

Do not put `tr()` inside `static let` values or enum raw values: those are evaluated once and would never switch language. Use computed properties.

## Add a shortcut action

Add an entry to `ShortcutAction.all` in `Shortcuts.swift` (id, group, title key, default `KeyCombo`, symbol) and handle its id in `AppState.run(_:)`. Defaults must not collide with another action or with a reserved macOS combination. The Shortcuts page and Quick Open pick it up automatically.

## Packaging

```bash
scripts/make-app.sh                              # dist/Vutidy.app, ad-hoc signed, for your machine
scripts/dev.sh                                   # the same, fast (debug), and opens it
ARCHS=universal scripts/package-macos.sh --build # dist/vutidy-<version>-macos.{dmg,zip,sha256}, Apple silicon + Intel
```

`make-app.sh` builds, creates the bundle (icon from `docs/assets/brand/AppIcon.icns`, `Info.plist` with bundle ID `com.vutidy.app`, the version from the `VERSION` file, minimum macOS 13), copies the resource bundles and signs it: ad-hoc by default, or with `CODESIGN_IDENTITY` (a real identity also turns on the Hardened Runtime and a timestamp). `package-macos.sh` then makes the disk image and the zip and the checksums. Variables: `CONFIG`, `ARCHS`, `CODESIGN_IDENTITY`, `DIST_DIR`, `BUILD_NUMBER`.

Releases are built and published by GitHub Actions, including optional Developer ID signing and notarization: see [Releasing](release.md). A stable signature also stops macOS from asking for Full Disk Access again after every build.

## Documentation screenshots

The images in `docs/assets/screens/` are generated, not hand-made, so they can be refreshed after a UI change:

```bash
CONFIG=debug scripts/make-app.sh          # build dist/Vutidy.app
scripts/capture-docs.sh                   # all screenshots (a few minutes)
scripts/capture-docs.sh quick-open confirm   # only some, by name
```

The script opens the app once per screenshot with environment variables (`VUTIDY_PAGE`, `VUTIDY_OPEN`, `VUTIDY_SETTINGS`, `VUTIDY_SCAN`, `VUTIDY_LANG`, `VUTIDY_SPACE`, see `AppState.init`), finds its window and captures it with `screencapture`. The terminal needs **Screen Recording** permission and `cwebp` must be installed (`brew install webp`). Images are WebP, 1800 px wide. They show *your* Mac's data (app names, sizes), so look at them before committing, and crop or retake any that expose a personal path.

## Brand and icon

The logo SVGs and the palette are in [docs/assets/brand](../assets/brand/README.md). To re-render the PNGs:

```bash
PLAYWRIGHT=/path/to/node_modules/playwright/index.mjs \
node docs/assets/brand/render.mjs '[{"svg":"logo-mark.svg","out":"logo-mark-1024.png","w":1024,"h":1024}]'
```

To rebuild `AppIcon.icns` from `appicon.png` (1024 px with a 100 px margin):

```bash
mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s appicon.png --out AppIcon.iconset/icon_${s}x${s}.png
  sips -z $((s*2)) $((s*2)) appicon.png --out AppIcon.iconset/icon_${s}x${s}@2x.png
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns
```

## Conventions

- Swift, 4-space indent, no force unwraps in logic that touches the disk.
- Everything user-facing goes through `tr()`/`trf()`.
- Anything that removes files goes through `ActionExecutor`.
- Documentation is in English.
- Run `scripts/check-doc-links.sh` after moving or renaming a document.
