# Niko Music Hub — UI design contract (binding, 2026-09-18)

This is the current design direction. It supersedes `docs/UI-REDESIGN-PLAN.md`
(historical) and is enforced by `Tests/AppCoreTests/HubDesignContractSourceTests.swift`
plus the older design guards. If a change needs to break a rule here, change the
rule and the test in the same commit — never "just this once".

The owner's bar: **"literally the same button positions, same cards, same heights"**
across pages. Do not eyeball alignment — measure it (see §7).

## 1. Window anatomy

```
┌───────────┬──────────────────────────────────────────┬───────────┬───────────┐
│ ●●● [⊟]‹› │ (title row, 44pt, inside every column)   │           │  [⊟]      │
│ tools     │ content column                           │ inspector │ Output    │
│ sidebar   │ (flexible)                               │ (tools    │ Inbox     │
│ 240pt     │                                          │ only)     │ 240pt     │
│           │                                          │ 240pt     │ (toggle)  │
└───────────┴──────────────────────────────────────────┴───────────┴───────────┘
```

- There is NO full-width title strip (Codex anatomy, measured 2026-09-18). Every
  column runs to the window top in its own material and reserves a 44pt title
  row inside itself (`HubShellLayout.titleBarHeight`, applied per column in
  `AppShellView`; nested rails read `hubTitleRowInset` from the environment and
  extend their material + seam through the row). The traffic lights and the
  title controls float on the column tones, centred on `titleBarAxisY` (22pt;
  Codex ≈ 23pt). The configurator re-centres the standard lights on that axis
  via their titlebar view's own (non-flipped) coordinates.
- Every chrome rail is `HubDesignSystem.Size.chromeRailWidth` (240) and uses
  `.hubChromeMaterial()`. Never a second width or a flat colour for a rail.
- Title-bar trailing inset == page side inset (16) so title-bar icons sit in the
  same x columns as page-header icons (`HubShellLayout.titleBarTrailingInset`).
- Title-bar rhythm is Codex-compact, NOT the page-header 30pt toolbar: 26pt
  buttons / 13pt glyphs (`HubShellTitleBarControls.buttonSize/glyphSize`), even
  8pt groups, and leading inset 99 (clears the repositioned lights + 14pt gap).
  Page-header actions keep 30pt / 14pt.
- One axis for lights + sidebar icons (`HubShellLayout.trafficAxisX` = 31):
  the configurator shifts the standard traffic lights (delta-based, preserving
  Apple spacing; skipped in Full Screen) until the close button centers over
  the row-icon column. The reverse is geometrically impossible (system lights
  at ~16pt; an 18pt icon frame in a 12-inset row bottoms out at a 21pt center).
- Back/forward = `HubNavigationHistory` (AppCore), created once in
  `AppComposition` and shared by BOTH `ToolContext`s. Tools with inner pages
  register a restorer (see `ArchiveBrowserViewModel+Navigation.swift`).
- The board⇄list switch is ONE flipping icon in the title bar
  (`ToolFeature.makeTitleBarAccessory`), never inside a page header.
- Output Inbox collapse threshold is derived: `540 + 2 × chromeRailWidth`.
  `toggleOutputInbox()` toggles the user's intent, not the width-derived state.

## 1.1 Chrome material — the Codex sidebar material, nothing over it (binding, 2026-09-18)

Verified with a red sheet behind both apps: Codex's rail went 220 →
rgb(249,218,215) light and 51 → rgb(82,48,46) dark — the standard AppKit
`.sidebar` vibrancy blended behind the window, which passes the colour behind
it through (boosted saturation) while blurring away every shape. Its content
column is opaque (dark rgb(45,45,43), light rgb(249,250,247)).

- Each chrome rail paints ONE bare `HubGlassBackdrop` =
  `HubVisualEffectView(.sidebar, .behindWindow)` on every macOS version.
  Nothing over it: any veil kills the bleed (a 0.30 white veil left
  rgb(213,213,211) over the same red), and `glassEffect` is a lens that keeps
  shapes readable (the "see-through sidebar" bug). Same red sheet behind ours
  now: rgb(222,201,197) light, rgb(80,35,35) dark. The rail tone therefore
  tracks the backdrop exactly like Codex's does (≈220 / ≈50 over neutral
  desktops). Column separation is the 1pt `Palette.separator` `shellDivider`.
- The window is a standard opaque window; inactive (non-key) rails go flat via
  the material's `.inactive` state, same as Codex. Reduce Transparency →
  opaque `Palette.sidebar`.
- The neutral dark scale is Codex's warm neutral, not inky blue-black: canvas
  45/45/43, sidebar 51/52/49, surface 55/55/53, raised 70/70/68, separator
  66/66/64. Light stays 249 / 224 / 246 / 250 / 222.
- Selection pill (`Palette.selection`) is a translucent neutral —
  `black 0.055` light, `white 0.09` dark — so it keeps Codex's step (−10 light,
  +15 dark) over whatever the rail renders.
- Launch leaves no keyboard focus on the sidebar toggle (the configurator clears
  the initial first responder once), so no focus ring shows before the user tabs.
- Title-bar and buttons stay flat and Codex-quiet per §6 (custom
  `HubPressableButtonStyle`, `.plain`, neutral fills). Apple's `.glass` button
  styles are intentionally NOT adopted.
- Accessibility is part of the material: Increase Contrast widens card strokes
  to 2pt; every token flips light/dark/high-contrast via `HubDynamicColor`.

## 1.2 Sidebar rhythm — Codex rows and captions (binding, 2026-09-18)

Measured from the Codex sidebar at 2×: rows pitch at 31pt, glyphs are thin
16pt outlines in the text tone, section captions ("Projekte") are body-size
regular grey text 43pt below the previous row centre and 31pt above the next.

- Rows are `Spacing.navRowHeight` = 30 with a 2pt gap (32 pitch), mirrored by
  every inspector control (`hubInspectorRow`, `HubSegmentedChoice`).
- Row glyphs: `.monochrome`, `.system(size: 15, weight: .light)` in an 18pt
  frame — never `.hierarchical` (reads heavier than the label).
- Sidebar captions are `ToolSidebarView.sidebarCaption`: `Typography.body()` in
  `Palette.textTertiary`, 10pt inner inset. Between groups: 6 top + a 30pt
  bottom-aligned frame + 8 bottom. The first caption ("Library") sits directly
  under the 56pt title band (16pt frame, 0 top, 8 bottom) so it shares the
  inspector's label keyline. `HubInspectorGroup` labels use the same
  body/tertiary style with an 8pt gap to the control and 20pt between groups.

## 2. Keylines (measured at the 1364×892 reference window, window-relative pt; title row 44 → all column keylines sit 14pt lower than the old 30pt strip)

| element | x | y | size |
|---|---|---|---|
| app mark text (sidebar) | 16 | 66 | 26 tall, `sectionTitle` |
| page title (any page) | 257 (= rail + 16 + 1 seam) | 66 | 26 tall, `screenTitle` |
| sidebar section header ("Library") | 22 | 120 | 16 tall, `body` tertiary |
| sidebar nav row | 12 | 144 | 216 × 30 |
| inspector group label | rail-inset 12 | 120 | 16 tall, `body` tertiary |
| inspector control | 12 from rail edge | 144 | 216 × 30 |
| primary object (tool card / board columns) | 257 | 140 | height 168 |
| pinned primary action | 12 from rail edge | window − 16 − 32 | 216 × 32 |

The sidebar and the inspector are mirror images: same inset, same row height,
same label keyline, same group spacing (second caption 194, second control 218
on both rails — measured). If one changes, the other changes.

## 3. One header, everywhere

`HubPageHeader` (AppCore) is the only page header: fixed 56pt band, `screenTitle`
title on a 30pt row, optional one-line status, trailing 30pt icon actions spaced
`controlGap`. Tool pages get it via `ToolHeaderBlock`; Board, Archive list,
Analytics and Output Inbox use it directly. **Never** hand-roll a title with
`.font(.system(size: 20…))` / `17…` — that is exactly the drift this contract ended.

## 4. Tool pages = `HubInspectorPage`

Every production tool (BPM Tapper, WAV Converter, Audio Recorder, Downloader,
Stem Separation) renders through `HubInspectorPage`:

- `header` — `ToolHeaderBlock(title:statusText:)`; status is `""`/nil when idle.
- `live` — exists only while something is happening (progress, "Recording saved",
  errors). Idle pages have no live strip.
- `primary` — the page's ONE bounded object at 168pt: drop zone, tap pad (with
  the 44pt `Typography.readout()` BPM), capture readout (timer), URL entry card.
- `list` — **scrolls** (the scaffold wraps it; header, live strip and the bounded
  object stay pinned). A flat `HubListSection` (`HubListRow`, hairlines, `HubListEmpty` one-liner)
  that is the page's content: Queue, Recent Tempos, Recordings, Details, Results.
  Produced files go through the shared `ToolOutputShelf` (keeps the drag-to-DAW
  handoff, HAND-03).
- `inspector` — `HubInspectorGroup(label) { control }` per option, in a fixed order.
- `action` — the primary `HubLabeledButton(style: .primary, expands: true)` FIRST;
  secondaries (Stop/Cancel/Retry/Reset/Copy) after it as `.ghost, expands: true`.
  `HubPrimaryLastStack` pins the first child to the bottom, so the primary lands on
  the same pixel on every tool regardless of how many secondaries exist.

### Wide pages (exception)
Archive Analytics is not a form — its charts use the FULL content column, never
the 680pt form cap (a capped chart strands half the window empty). Board ⇄
Analytics is ONE flipping `chart.bar` icon in the last header-trailing slot on
both pages (selected while in Analytics, Esc works too) — going there and back
never moves under the cursor. Same pattern as the board⇄list title-bar flip (§1).

### Inspector controls — one silhouette
- Two or more fixed options → `HubSegmentedChoice` (one control, nav-row height,
  chosen cell filled like a selected sidebar row). Use `columns:` for grids
  (Format 2×2, Sample rate 2×2). `HubChoiceChips` only where wrapping tag-style
  chips are genuinely better (currently nowhere in inspectors).
- Text fields, sliders, path readouts, popup rows → `.hubInspectorRow()` (30pt,
  flat like a sidebar row — no raised fill). Focus adds the ring.
- Nothing in an inspector may change height with state. Conditional info
  (e.g. playlist cap) goes in a tooltip or the left list, never as a line that
  appears below a control.
- Currently hidden by owner decision (keep hidden unless told): BPM multiplier,
  Downloader "Channel" mode, Stems "Experimental 6-stem".

### Adding a tool page
Copy `StemSeparationView.swift` as the template. Fill the six slots, use only the
components above, then run the measurement loop (§7) and compare against §2.

## 4b. Settings and selection

Settings panes are grouped forms: a caption header above a card, rows inside the
card (`SettingsRow` label + optional one-line description on the left, control
flush right), `SettingsRowDivider` hairlines inset to the label's leading edge,
an optional footer caption under the card. Few cards, many rows — never one card
per setting, and never a field surface nested inside the card.

The Settings window is fixed 744pt wide with the form column centered, so leftover
width splits evenly left/right (measured 96px/96px). Quirk to preserve:
`hubToolContentColumn`'s 680 cap *includes* its own horizontal padding, so the
real content is 648 wide — size any centering box to exactly 680, never 680+32,
or the phantom slack pools on the right again (leading-anchored).

A selected row (sidebar nav row, segmented cell) is a flat Codex-quiet pill:
`Palette.selection` — a translucent neutral (black 0.055 light / white 0.09 dark)
that reads darker than the rail in light and a small step lighter in dark, the
measured Codex step (§1.1) — no sheen, no rim, no shadow. Every row label
renders at full strength — the pill alone carries the state, exactly like the
ChatGPT/Codex sidebar. Sidebar rows and inspector cells use the same treatment.

## 4c. Accent: warm indicator, neutral everything else

One warm colour exists: `Palette.indicator` (terracotta `#CC7D5E` light /
`#DB8D6C` dark) with `Palette.indicatorDeep` for hover/press. It goes ONLY on:
toggles, sliders, progress bars, primary `HubLabeledButton`s (one per tool page),
and running `StatusDot`s. Everything else stays neutral like the Codex sidebar:
selection pill, links, secondary/ghost buttons, chips, text.

Why two tokens: DS-12/DS-13 guards pin `Palette.accent` achromatic (R≈G≈B) and
forbid accent-tinted selection. The warm colour is a SEPARATE token, so the
guards keep passing and no test needs weakening to see colour. If a new surface
wants warmth, add it to the allowlist above AND this section in the same commit —
never point a new consumer at `accent` expecting warmth.

## 5. Copy (omitting-ui-chrome)

- Title = the object. No subtitle unless it carries a constraint/scope/status.
  `ToolHeaderBlock.statusText` is optional; idle "Ready…" strings are `""`.
- Helper text only for a constraint or format ("M4A, MP3, WAV, AIFF, or FLAC").
- Empty state = one line naming the missing object ("No files queued").
- Empty states are bare content on the background — icon + text, never a card.
  (A white card screams once everything around it goes flat.)
- Buttons = verb + noun. Banned: "Welcome to", "Manage your", "This page lets you",
  "Use this to", "Easily", "Simply".

## 6. Focus, colour, shape

- **Every `.focusable()` / `.focusable(true)` pairs with `.focusEffectDisabled()`.**
  AppKit's system focus ring is blue; the app's ring is `Palette.focus` (grey), drawn
  by the component, and for whole-pane focus only when
  `NSApp.isFullKeyboardAccessEnabled`.
- Zero system blue. No `.bordered*`, `.glass*`, segmented `Picker`, `Color.white`
  fills, `.roundedBorder` fields. Buttons share `Radius.button` — no `Capsule()`
  buttons.
- Cards only for bounded objects with a role (drop target, readout, queue item).
- Big live numbers use `Typography.readout()` (44pt rounded, tabular).

## 7. Verification loop (do this, every time)

**Verify every page with a FULL list, not an empty one.** An empty fixture hid a
content-column overflow that shipped to a local install: 28 stem results grew the
column past the window and clipped the sidebar. Seed the isolated suite's
`output-inbox.json` (`~/Library/Application Support/Niko Music Hub/Isolated/<suite>/`)
with real-looking rows, and check light appearance too — both were blind spots.


1. `swift build && swift test` (source guards live in `Tests/AppCoreTests/*Source*Tests`).
2. Launch the dev bundle with the fixture archive (`script/lib/app_lifecycle.sh`
   `nmh_build_bundle`, then `open --env NIKO_MUSIC_HUB_FIXTURE_ROOT=… --env
   NIKO_MUSIC_HUB_SETTINGS_SUITE=<fresh> --env NIKO_MUSIC_HUB_DRY_RUN_OPEN=1`).
3. Resolve the dev PID (`pgrep -f dist/NikoMusicHub.app/Contents/MacOS/NikoMusicHub`) —
   never target the app by name; stale copies may be running.
4. Dump accessibility frames (window-relative) for the page and compare to §2.
   A small AX walker (role, id/description, x,y, w×h) is all it takes; the window
   title is the selected tool's name.
5. Screenshot per page and look at it. Numbers first, eyes second.

## 8. Working with subagents on UI

- Muse (OpenCode) edits are fine for mechanical ports; the runner holds a
  per-workspace lock, so run page jobs sequentially. Give it the exact slot mapping
  and the component names; it does not measure — you do.
- Anthropic relay agents die on session limits; call `worker.py` directly then.
- Muse will silently drop functionality (preset editor, `ToolOutputShelf`). The
  source guards catch the known cases; read the diff for the rest.
