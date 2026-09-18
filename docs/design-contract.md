# Niko Music Hub — UI design contract (binding, 2026-09-18)

This is the current design direction. It supersedes `docs/UI-REDESIGN-PLAN.md`
(historical) and is enforced by `Tests/AppCoreTests/HubDesignContractSourceTests.swift`
plus the older design guards. If a change needs to break a rule here, change the
rule and the test in the same commit — never "just this once".

The owner's bar: **"literally the same button positions, same cards, same heights"**
across pages. Do not eyeball alignment — measure it (see §7).

## 1. Window anatomy

```
┌ title bar (30pt, hidden native title) ───────────────────────────────────────┐
│ ●●● [sidebar] [‹][›]                     [tool accessory] [inbox toggle]      │
├───────────┬──────────────────────────────────────────┬───────────┬───────────┤
│ tools     │ content column                           │ inspector │ Output    │
│ sidebar   │ (flexible)                               │ (tools    │ Inbox     │
│ 240pt     │                                          │ only)     │ 240pt     │
│           │                                          │ 240pt     │ (toggle)  │
└───────────┴──────────────────────────────────────────┴───────────┴───────────┘
```

- Every chrome rail is `HubDesignSystem.Size.chromeRailWidth` (240) and uses
  `.hubChromeMaterial()`. Never a second width or a flat colour for a rail.
- Title-bar trailing inset == page side inset (16) so title-bar icons sit in the
  same x columns as page-header icons (`HubShellLayout.titleBarTrailingInset`).
- Back/forward = `HubNavigationHistory` (AppCore), created once in
  `AppComposition` and shared by BOTH `ToolContext`s. Tools with inner pages
  register a restorer (see `ArchiveBrowserViewModel+Navigation.swift`).
- The board⇄list switch is ONE flipping icon in the title bar
  (`ToolFeature.makeTitleBarAccessory`), never inside a page header.
- Output Inbox collapse threshold is derived: `540 + 2 × chromeRailWidth`.
  `toggleOutputInbox()` toggles the user's intent, not the width-derived state.

## 2. Keylines (measured at the 1364×892 reference window, window-relative pt)

| element | x | y | size |
|---|---|---|---|
| app mark text (sidebar) | 16 | 52 | 26 tall, `sectionTitle` |
| page title (any page) | 257 (= rail + 16 + 1 seam) | 52 | 26 tall, `screenTitle` |
| sidebar section header ("Library") | 12 | 106 | 14 tall |
| sidebar nav row | 12 | 124 | 216 × 34 |
| inspector group label | rail-inset 12 | 106 | 14 tall |
| inspector control | 12 from rail edge | 124 | 216 × 34 |
| primary object (tool card / board columns) | 257 | 126 | height 168 |
| pinned primary action | 12 from rail edge | window − 16 − 32 | 216 × 32 |

The sidebar and the inspector are mirror images: same inset, same row height,
same label keyline, same group spacing (16). If one changes, the other changes.

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
- Text fields, sliders, path readouts, popup rows → `.hubInspectorRow()` (34pt,
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
`Palette.selection` fill (gray, darker than the rail in light mode), no sheen,
no rim, no shadow. Every row label renders at full strength — the pill alone
carries the state, exactly like the ChatGPT/Codex sidebar. Sidebar rows and
inspector cells use the same treatment.

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
