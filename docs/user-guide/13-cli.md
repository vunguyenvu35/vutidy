# Command line

`vutidy-cli` runs the same scanners and the same safety layer from a terminal, which is handy over SSH or in a script.

## Contents

- [Run it](#run-it)
- [Commands](#commands)
- [Examples](#examples)
- [Environment](#environment)
- [Limits](#limits)

## Run it

```bash
swift run vutidy-cli <command>
# or, after a build:
.build/debug/vutidy-cli <command>
```

## Commands

| Command | What it does |
| --- | --- |
| `scan <system\|dev\|trash\|privacy\|all> [--projects DIR,DIR]` | Lists what could be cleaned, grouped, with size and safety. `[x]` marks items that would be selected. |
| `clean <system\|dev\|trash\|privacy> [--mode dry\|trash\|quarantine] [--include-review] [--projects DIR]` | Cleans. **Dry-run unless you pass `--mode trash` or `--mode quarantine`.** Only *Safe* items, unless `--include-review`. |
| `space <path>` | The biggest children of a folder. |
| `duplicates <path>` | Groups of identical files and the space they waste. |
| `large <path> [--min-mb N] [--days N]` | Large (and optionally old) files. |
| `quarantine list` | Items in the Quarantine with days left. |
| `quarantine restore <ID>` | Restores one item to its original path. |
| `quarantine purge-expired` | Deletes items past their retention. |
| `audit` | The last 50 entries of the audit log. |

The blocklist, the running-app checks and the audit log apply exactly as in the app.

## Examples

```bash
vutidy-cli scan dev --projects ~/Projects,~/Code     # what Dev Junk finds
vutidy-cli clean system                              # dry-run: lists what would happen
vutidy-cli clean system --mode quarantine            # really do it, safe items only
vutidy-cli quarantine list
vutidy-cli quarantine restore 5F1C…                  # undo
vutidy-cli space ~/Library
```

## Environment

| Variable | Effect |
| --- | --- |
| `VUTIDY_HOME` | Use this folder instead of `~/Library/Application Support/Vutidy` for the Quarantine, audit log and rules. Useful for tests. |

## Limits

- Output is in Vietnamese for now (the app itself is localized).
- There is no `--yes` flag because `clean` never prompts; the dry-run default is the safety.
- Smart Scan, Protection and the Speed pages are not exposed in the CLI.
