# Design spec: Graphite Glass

> Version v3 · 2026-11-10 · App name: **Vutidy**
> The first mock-ups (canvas "Mac Cleaner UI") are in [`source/`](source); the machine-readable tokens are in [`tokens/`](tokens) (`tokens.json`, `tokens.css`, `Theme.swift`). Sections 7 onward describe the **redesign** that replaced the first screens.

## Contents

- [1. Direction](#1-direction)
- [2. Design tokens](#2-design-tokens)
- [3. Window layout](#3-window-layout)
- [4. Screens](#4-screens)
- [5. Components](#5-components)
- [6. States and interaction](#6-states-and-interaction)
- [7. Redesign: the CleanMyMac-style pass](#7-redesign-the-cleanmymac-style-pass)
- [8. Settings window](#8-settings-window)
- [9. Accessibility](#9-accessibility)
- [10. Still missing](#10-still-missing)

## 1. Direction

- **Feel:** a serious, trustworthy native macOS app. It can delete files, so the UI must create a feeling of safety and transparency before it creates a "wow".
- **Principles:**
  1. Numbers are the hero: large, clear, in their own display face.
  2. One signal colour (mint) for safe actions. Amber for everything the user should look at again.
  3. Always show how to undo: the 7-day Quarantine, dry-run and the commands to run are visible in the UI.
  4. No decorative gradient in content, no emoji, no coloured left border on cards.
- **Window:** a translucent sidebar (vibrancy, `NSVisualEffectView` material `.sidebar`), a slim top bar, solid content.

## 2. Design tokens

### 2.1 Colour

| Token | Value | Use |
| --- | --- | --- |
| `bg.content` | `#0F1217` | Content background |
| `bg.card` | `#151920` | Regular card |
| `bg.hero` | `#171C25 → #131720` | Featured card (hero, summary) |
| `bg.code` | `#0A0C10` | Command and path blocks |
| `bg.sidebar` | `rgba(26,30,39,0.66)` + blur | Sidebar (native uses vibrancy) |
| `border.subtle` | `rgba(255,255,255,0.06)` | Card border |
| `border.default` | `rgba(255,255,255,0.10)` | Secondary button, input |
| `text.primary` | `#EDF0F4` | Main text |
| `text.secondary` | `#A6B0BD` | Secondary text (≥ 4.5:1 on `bg.card`) |
| `text.tertiary` | `#8A95A3` | Small labels, placeholders |
| `signal` | `#3DDC97` | Safe action, CTA, good state |
| `review` | `#F2B13A` | Needs a look, warning |
| `info` | `#5AA9FF` | System, information |
| `apps` | `#A78BFA` | Applications |
| `danger` | `#FF8A7A` | Dangerous (rare) |

The redesign adds three accent colours used for per-page identity: **teal** `#2DD4D4`, **orange** `#FF9F5A`, **pink** `#FF6FA5` (`Theme.teal/orange/pink` in `DesignSystem.swift`).

### 2.2 Type

| Role | Face | Size / weight |
| --- | --- | --- |
| Display (big numbers) | SF Pro Rounded | 24–40 / 700, tabular digits |
| Title | SF Pro Display | 26–32 / 700 |
| Heading | SF Pro Text | 15 / 600 |
| Body | SF Pro Text | 13.5–14 / 400–500 |
| Label | SF Pro Text | 11–12 / 600 (uppercase for section labels) |
| Mono | SF Mono | 12 (paths, commands) |

### 2.3 Spacing and radius

Spacing 4 · 8 · 12 · 16 · 20 · 24 · 32. Radius: nav item 10 · button 9–12 · card 16 · hero 18 · icon tile ≈ 29 % of its size. Minimum hit target 32 pt in the sidebar, 44 pt for the primary action.

## 3. Window layout

```
┌───────────────┬───────────────────────────────────────────────┐
│ ● ● ●         │                          🌐 English  ● Real-time │ ← top bar 48pt
│ [V] Vutidy    ├───────────────────────────────────────────────┤
│               │                                               │
│ Smart Scan    │   Page header: coloured icon, title, caption  │
│ CLEANUP       │                                               │
│  ▣ System Junk│   Page content                                │
│  ▣ Dev Junk   │                                               │
│  ▣ Trash      ├───────────────────────────────────────────────┤
│ PROTECTION    │  Action bar (cleanup pages): selected · mode  │
│ …             │                                    [Clean 2 GB]│
│ [Quarantine]  │                                               │
└───────────────┴───────────────────────────────────────────────┘
  sidebar 264pt              content
```

- **Sidebar:** grouped by area. Each item has a **solid gradient icon in the colour of its page**; the active item has a white 10 % background. Pointing at an item shows its shortcut. The **Quarantine card** at the bottom is the always-visible safety net.
- **Top bar:** no title (the page header carries it): language menu, real-time switch, settings gear.
- **Cleanup pages** own their scrolling so the action bar can be pinned at the bottom.

## 4. Screens

### 4.1 Smart Scan

| Zone | Content |
| --- | --- |
| Header | Date + "Your Mac can get back **24.8 GB**" + Rescan |
| Hero | Outer ring: disk (used, purgeable, free). Centre: free space now → after cleaning. Right: **Clean**, **Preview (dry-run)**, "Undoable for 7 days" |
| Three cards | **Cleanup**: sizes by module. **Protection**: three counters. **Speed**: memory and a CPU sparkline |

### 4.2 Cleanup pages (System Junk, Dev Junk, Trash, Privacy)

Before a scan, a centred **ScanHero** (large coloured icon with a soft glow, title, description, big **Scan** button). After a scan: header with the total, filter chips (*All / Safe / Review* with counts), then **category cards**: a select circle, a coloured icon for the source (Docker, JetBrains, Cache…), name, a share-of-total bar, item count, size and a chevron. A card expands into item rows (path or `$ command`, *CLI* tag, *Review* badge, size). The **action bar** is pinned at the bottom.

### 4.3 Space Lens

Breadcrumb pills; **Treemap** or **List**. The treemap splits space by size (balanced binary split), colours by position; the selected tile has a signal border. A detail panel shows name, path, size, context warnings (Docker.raw) and actions.

### 4.4 Menu bar popover

400 pt wide. Recommendation cards with **‹ ›** buttons and dots (a mouse cannot drag a horizontal scroller), the real-time switch, then a two-column grid: Disk, Memory, CPU + sparkline, Battery, Network + speed test, Devices, and a footer (Open Vutidy, Quit).

### 4.5 Optimization, Maintenance, Protection, Updates, Quarantine

Rebuilt on the shared design system (section 7). See [Speed](../user-guide/05-speed.md), [Protection](../user-guide/04-protection.md) and [Quarantine and safety](../user-guide/08-quarantine-and-safety.md).

## 5. Components

| Component | Variants | Rule |
| --- | --- | --- |
| Button | Primary (mint, dark text, soft glow), Secondary (bordered), Text action | One Primary per screen |
| Safety badge | Safe / Review / Dangerous / Info | Always has a word, never colour alone |
| Chip picker | 2–4 options, pill track | Replaces the default segmented control |
| Switch | native small switch, mint tint | Settings and startup items |
| Card | regular / hero / flat (no padding) | Hero for the main figure and action panels |
| Ring / Gauge | disk ring, gauge tile, days-left ring | 2–3 pt gaps between segments |
| Code block | commands to run | `$` prefix; dry run shown as a comment |
| Key cap | one cap per key, highlight while recording | Used in Shortcuts and Quick Open |

## 6. States and interaction

- **Scanning:** the ScanHero shows a spinner and the current rule; cards appear when there is data.
- **Cleaning:** one-step confirmation (total and mode), then a toast "Moved 24.8 GB to Quarantine · Undo".
- **Empty:** the hero says "Your Mac is tidy" with no CTA.
- **Permission:** missing Full Disk Access shows an amber banner (dismissible, only on the pages that need it) with *Open System Settings* and *Reveal app in Finder*.
- **Motion:** only for scan progress and screen changes (≤ 200 ms). **Reduce motion** in Settings turns it off.

## 7. Redesign: the CleanMyMac-style pass

The first screens were plain tables. The redesign (shared code in `Sources/Vutidy/DesignSystem.swift`) follows the layout language of CleanMyMac: focused pages, a big coloured icon, one primary button, category cards and an action bar. No name, logo or artwork of that product is used.

| Piece | File / type | Purpose |
| --- | --- | --- |
| Page colours | `Page.tint` | Each sidebar item and page header has its own colour |
| `SolidIcon` | DesignSystem | Gradient rounded icon with a dark glyph; sidebar, hero, headers |
| `IconTile` | DesignSystem | Tinted translucent icon tile for rows and cards |
| `ScanHero` | DesignSystem | Centred pre-scan / empty / done state with glow and primary button |
| `SectionCard` | DesignSystem | Card with an icon, title, subtitle, trailing control and rows |
| `ListRow` | DesignSystem | Icon · title/subtitle · controls, with hover and a divider |
| `GaugeTile` | DesignSystem | Ring gauge with a big value and caption (Optimization) |
| `MeterBar` | DesignSystem | Thin proportional bar (CPU, category share) |
| `ChipPicker` | DesignSystem | Pill-shaped filter |
| `SwitchRow` | DesignSystem | Native switch with a label |
| `AppIconView` / `AppLookup` | DesignSystem | Real app icons from a bundle or a running process |
| `CategoryStyle` | CleanupView | Icon + colour for each cleanup source |
| `PageHeader` | Components | Solid page icon + title + caption (+ trailing action) |
| `LogoMark` | Components | The logo drawn in SwiftUI |

Layout changes: the toolbar title was removed (duplicated the header), nav badges were removed (they truncated names), the summary side panel was replaced by the pinned action bar (it was clipped on small windows), and the Full Disk Access banner shows only where it matters.

## 8. Settings window

Modelled on Vutty's. A **floating window over the app** (not a separate macOS window): a title bar with a gear, "Settings", maximize and close; a left menu in groups (**PREFERENCES** General, Cleaning, Protection · **ADVANCED** Shortcuts, Storage · **HELP** Support Vutidy, version); a centred content column with a page title, a caption, a divider, then **setting groups** (cards with an uppercase header) made of rows (bold title and description on the left, the control on the right). The Shortcuts page shows key caps; clicking one records a new combination. Esc, a click outside and × close it; changes apply immediately. See [Settings](../user-guide/10-settings.md).

## 9. Accessibility

- Text contrast ≥ 4.5:1 (11 px labels use `text.secondary`, not `text.tertiary`).
- Category colours differ in lightness, not only hue.
- Every icon-only button has a label (VoiceOver); key caps and charts expose a text description.
- Honour **Reduce motion**; Increase Contrast should raise `border.subtle` to 0.16 (not done yet).

## 10. Still missing

- [ ] Light mode
- [ ] Increase Contrast adjustments
- [ ] First-run onboarding for Full Disk Access (only the banner exists)
- [ ] A scheduler UI (scan schedule) and notifications
- [ ] Redesign pass for Uninstaller, Space Lens detail panel and Settings polish on small windows
