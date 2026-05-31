# Niko Music Hub -- Full UI Redesign Plan

> **Purpose**: A handoff-ready specification that any engineer or AI model can follow to
> produce the exact intended outcome. Every decision is justified, every pixel placement
> is specified, and every file that needs changing is listed.
>
> **Design direction**: Clean, friendly, modern IDE-style shell with Apple Liquid Glass
> native aesthetics. Think Xcode meets Apple Music meets Linear -- warm, confident, quiet.

---

## Table of Contents

1. [Current State Diagnosis](#1-current-state-diagnosis)
2. [Design Philosophy & Guiding Principles](#2-design-philosophy--guiding-principles)
3. [Design System Overhaul](#3-design-system-overhaul)
4. [Shell Layout Redesign](#4-shell-layout-redesign)
5. [Tool Sidebar Redesign](#5-tool-sidebar-redesign)
6. [Output Inbox Redesign](#6-output-inbox-redesign)
7. [Archive Browser Redesign](#7-archive-browser-redesign)
8. [BPM Tapper Redesign](#8-bpm-tapper-redesign)
9. [WAV Converter Redesign](#9-wav-converter-redesign)
10. [Audio Recorder Redesign](#10-audio-recorder-redesign)
11. [Downloader Redesign](#11-downloader-redesign)
12. [Settings Redesign](#12-settings-redesign)
13. [Shared Component Library](#13-shared-component-library)
14. [Implementation Order](#14-implementation-order)
15. [File Manifest](#15-file-manifest)

---

## 1. Current State Diagnosis

### 1.1 What works

- **Three-column shell**: The left sidebar / center content / right inbox layout is correct
  for a tool-centric app. Keep it.
- **Glass material system**: `HubGlassPanel`, `HubGlassCard` provide a frosted-glass
  foundation. The concept is right; the execution needs refinement.
- **Design token structure**: `HubDesignSystem` with `Radius`, `Spacing`, `Typography`
  enums is a good skeleton. It needs to grow, not be replaced.
- **Accessibility**: Every button has an accessibility label. The `HubIconButton` has
  `help` tooltips. This must be preserved throughout the redesign.

### 1.2 Global problems (affect every page)

| Problem | Evidence | Impact |
|---------|----------|--------|
| **Icon-only buttons with no labels** | `HubIconButton` renders as a 28x28 icon square. Users cannot tell what buttons do without hovering for the tooltip. | Severe usability failure. Every primary action is a mystery. |
| **Inconsistent button sizing** | Some actions use `.bordered`, some `.borderedProminent`, some `HubIconButton`. The Archive detail view has a mix of all three within 20px of each other. | Visual chaos; no hierarchy. |
| **No content max-width on wide screens** | Tool views set `maxWidth: 720` but the center panel stretches to fill. On a maximized 1440px window, the center has ~1000px but content is left-aligned in a 720px column with 280px of dead space to the right. | Feels broken at large sizes. |
| **Overly dark, flat, monotone** | The shell background uses `windowBackgroundColor` plus two faint radial gradients. In dark mode, the entire app is a uniform dark gray with no visual relief. Cards blend into panels; panels blend into the background. | Every surface looks the same. Nothing pops. |
| **Typography is entirely system font** | Every text uses `.system(size:weight:)`. No typographic personality. The rounded design variant is used only for the sidebar app name and section titles. | Generic; could be any app. |
| **No empty-state illustrations** | Empty states are just a system icon + two lines of text in gray. The Archive's "Select a song" and the Converter's "Drop files" look identical. | Cold, uninviting. |
| **Section dividers are invisible** | `Divider().opacity(0.4)` is barely perceptible. There is no visual grouping of related controls. | Sections blur together. |
| **Color usage is purely semantic** | The only colors are `.accentColor` (system blue), `.red`, `.orange`, `.green`, `.secondary`. No brand color, no warmth. | No identity. |

### 1.3 Per-page problems

#### Archive Browser
- Song cards in the sidebar have zero visual hierarchy -- title, subtitle, and mini-player
  all use similar gray tones at tiny sizes
- The detail pane scrolls endlessly with no visual sectioning -- metadata, collaborators,
  preview, actions, CPR list, alternate previews all flow together
- The waveform hero play controls (`-5s`, play, `+5s`) use raw button labels, creating
  a jarring mix with the icon-only `HubIconButton` pattern used everywhere else
- Filter chips in the sidebar (`Has Stems`, `Recently Bounced`, etc.) are small and
  use the same muted style whether selected or not
- The `ArchiveDesignTokens` enum is redundant -- it just aliases `Color.clear`,
  `Color.accentColor`, `Color.primary`, etc. with no added value

#### BPM Tapper
- The tap surface is too small (320x180px ideal) for a feature that needs a large hit target
- The BPM readout at `size: 40` is modest; this should be the hero element
- The segmented picker for `Original / Half-Time / Double-Time` uses stock macOS styling
  that clashes with the glass aesthetic
- The `Recent Tempos` history section has no visual separation from the tap workflow
- Action buttons (Copy, Save, Reset) are three identical icon-only squares in a row --
  no label, no hierarchy

#### WAV Converter
- The drop zone uses a thin 1px border that is nearly invisible in dark mode
- The preset strip (`44.1 kHz - 24-bit - Preserve mono/stereo`) is a dense text line
  with a tiny settings icon -- users miss that it's editable
- Action buttons (`+`, convert, stop) are three icon-only squares with no labels
- Batch rows are dense and hard to scan: source name, planned output, status text,
  and progress bar all compete for attention

#### Audio Recorder
- The time display (`00:00:00` at `size: 32`) feels small for a recording interface
  where the timer is the primary feedback
- The `Record` / `Stop` button is a stock `.bordered` button with a label -- good,
  but inconsistent with the icon-only pattern used on every other page
- The meter bar is a raw rectangle with no polish -- no rounded caps, no gradient,
  no glow
- Max Duration segmented picker feels disconnected from the recording controls

#### Downloader
- The URL text field uses stock `.roundedBorder` which clashes with the glass cards
- The format selection card is good but has no visual emphasis
- Action buttons (download, clear) are icon-only with no labels
- The trust-info card is a wall of small gray text that users will skip

#### Settings
- Long vertical scroll with no grouping beyond section titles
- `SettingsSection` cards all look identical -- there's no hierarchy between critical
  settings (archive roots) and informational ones (About)
- Helper tools section is confusing: three identical `folder` buttons for
  FFmpeg / ffprobe / yt-dlp with no differentiation
- The privacy section has a lock icon button that is easy to miss

---

## 2. Design Philosophy & Guiding Principles

### 2.1 North Star

**"A music producer's trusted workshop"** -- warm wood and clean tools, not a cold
operating theater. Every screen should feel like opening a well-organized instrument case.

### 2.2 The Seven Rules

1. **Every action button gets a label.** Icon + short text. No exceptions for primary
   actions. Secondary/tertiary actions may use icon-only if the context makes the
   meaning unambiguous (e.g., a `folder` icon next to a file path).

2. **Parallel lines, parallel elements.** If two buttons are side by side, they must be
   the same height. If two cards are in a column, their left edges must align. If a
   section has a title + body + footer, the spacing between them must be consistent
   with every other section.

3. **Three levels of visual emphasis.** Primary (filled accent), Secondary (bordered),
   Tertiary (plain/ghost). No mixing within a single action row.

4. **Cards for bounded content; no cards for flowing content.** A song in a list gets
   a card. A settings section gets a card. A long scrolling detail view does NOT get a
   card around each metadata field -- use dividers and whitespace instead.

5. **Warm accent, cool background.** The accent color shifts from raw system blue to
   a warm indigo-blue. The shell background stays cool-neutral.

6. **Motion is purposeful.** Hover states on buttons and cards. Selection transitions.
   No gratuitous animation.

7. **Density matches the page's purpose.** The Archive sidebar is dense (many songs,
   scan fast). The BPM Tapper is spacious (one big target). The Settings page is
   medium density with generous section spacing.

---

## 3. Design System Overhaul

### 3.1 File: `Sources/AppCore/Components/HubDesignSystem.swift`

Replace the current contents entirely:

```swift
public enum HubDesignSystem {

    // MARK: - Corner Radii
    public enum Radius {
        public static let shell: CGFloat = 14       // was 16 -- tighter is more modern
        public static let panel: CGFloat = 12       // was 14
        public static let card: CGFloat = 10        // was 12
        public static let row: CGFloat = 8          // was 10
        public static let chip: CGFloat = 6         // was 8
        public static let pill: CGFloat = 18        // was 20 -- used for search fields
        public static let button: CGFloat = 8       // NEW -- for labeled buttons
    }

    // MARK: - Spacing
    public enum Spacing {
        public static let shell: CGFloat = 10       // was 14 -- tighter gap between panels
        public static let panel: CGFloat = 16       // unchanged
        public static let section: CGFloat = 24     // was 20 -- more breathing room
        public static let cardGap: CGFloat = 8      // NEW -- between cards in a list
        public static let controlGap: CGFloat = 8   // NEW -- between buttons in a row
        public static let inlineGap: CGFloat = 6    // NEW -- between icon and label
    }

    // MARK: - Sizes
    public enum Size {
        public static let sidebarIconFrame: CGFloat = 18   // SF Symbol frame
        public static let buttonMinHeight: CGFloat = 32    // all labeled buttons
        public static let iconButtonSize: CGFloat = 30     // was 28 -- slightly larger
        public static let chipHeight: CGFloat = 26         // NEW
        public static let statusDot: CGFloat = 7           // was 8 -- subtler
        public static let sidebarWidth: ClosedRange<CGFloat> = 200...260
        public static let inboxWidth: ClosedRange<CGFloat> = 260...320
    }

    // MARK: - Colors
    public enum Colors {
        /// Warm indigo accent -- replaces raw .accentColor everywhere
        public static let accent = Color(red: 0.35, green: 0.42, blue: 0.95)
        /// Lighter tint for subtle backgrounds (selected rows, hover)
        public static let accentTint = accent.opacity(0.12)
        /// Deeper accent for pressed / prominent states
        public static let accentDeep = Color(red: 0.28, green: 0.34, blue: 0.82)
        /// Success
        public static let success = Color(red: 0.30, green: 0.78, blue: 0.48)
        /// Warning
        public static let warning = Color(red: 0.95, green: 0.68, blue: 0.25)
        /// Error
        public static let danger = Color(red: 0.92, green: 0.34, blue: 0.34)
        /// Subtle separator
        public static let separator = Color.primary.opacity(0.08)
        /// Card stroke
        public static let cardStroke = Color.primary.opacity(0.07)
        /// Selected row stroke
        public static let selectedStroke = accent.opacity(0.35)
    }

    // MARK: - Glass
    public static var glassStroke: Color { Colors.cardStroke }
    public static var glassInnerHighlight: Color { Color.white.opacity(0.10) }
    public static var selectedRowFill: Color { Colors.accentTint }
    public static var selectedRowStroke: Color { Colors.selectedStroke }

    // MARK: - Typography
    public enum Typography {
        // Display -- hero numbers (BPM readout, timer)
        public static func display() -> Font {
            .system(size: 56, weight: .bold, design: .rounded)
        }
        // Screen title -- page headers
        public static func screenTitle() -> Font {
            .system(size: 18, weight: .semibold, design: .rounded)
        }
        // Section title -- within a page
        public static func sectionTitle() -> Font {
            .system(size: 14, weight: .semibold, design: .rounded)
        }
        // Body
        public static func body() -> Font {
            .system(size: 13, weight: .regular)
        }
        // Small body -- secondary text
        public static func bodySmall() -> Font {
            .system(size: 12, weight: .regular)
        }
        // Caption -- labels, footers
        public static func caption() -> Font {
            .system(size: 11, weight: .medium)
        }
        // Micro -- badges, status dots
        public static func micro() -> Font {
            .system(size: 10, weight: .medium)
        }
        // Mono -- time displays, log text
        public static func mono(size: CGFloat = 13) -> Font {
            .system(size: size, weight: .medium, design: .monospaced)
        }
    }
}
```

### 3.2 File: `Sources/AppCore/Components/HubGlassChrome.swift`

**Shell background** -- increase the gradient intensity for more depth:

```
// ambientColors (dark mode):
Color(red: 0.12, green: 0.13, blue: 0.19).opacity(0.65)  // was 0.55
// secondaryAmbientColors (dark mode):
Color(red: 0.08, green: 0.10, blue: 0.15).opacity(0.50)   // was 0.45
```

**HubGlassPanel** -- increase shadow for more lift:

```
shadow radius: 18 (was 14), y: 6 (was 5)
dark opacity: 0.40 (was 0.35)
```

**HubGlassCard** -- add a subtle inner top highlight for glass depth:

```
// After the strokeBorder overlay, add:
.overlay(alignment: .top) {
    shape
        .fill(
            LinearGradient(
                colors: [Color.white.opacity(0.06), .clear],
                startPoint: .top,
                endPoint: .center
            )
        )
        .allowsHitTesting(false)
}
```

**HubSidebarNavRow** -- rounder pill, softer selected state:

```
cornerRadius: HubDesignSystem.Radius.row  // keep
fill: HubDesignSystem.Colors.accentTint   // use new token
stroke: HubDesignSystem.Colors.selectedStroke  // use new token
```

### 3.3 File: `Sources/FeatureArchiveBrowser/ArchiveDesignTokens.swift`

**Delete this file entirely.** Replace all references with `HubDesignSystem.Colors`:

| Old token | New token |
|-----------|-----------|
| `ArchiveDesignTokens.background` | `Color.clear` (inline) |
| `ArchiveDesignTokens.surface` | `Color.clear` (inline) |
| `ArchiveDesignTokens.accent` | `HubDesignSystem.Colors.accent` |
| `ArchiveDesignTokens.warning` | `HubDesignSystem.Colors.warning` |
| `ArchiveDesignTokens.textPrimary` | `Color.primary` (inline) |
| `ArchiveDesignTokens.textSecondary` | `Color.secondary` (inline) |

This affects 16 files (see File Manifest at the bottom).

---

## 4. Shell Layout Redesign

### File: `Sources/NikoMusicHub/AppShell/AppShellView.swift`

#### 4.1 Panel gaps

Change `Spacing.shell` from 14 to 10. The panels should feel like they're part of one
surface with subtle seams, not floating islands.

#### 4.2 Content centering

Remove `maxWidth: .infinity` left-alignment from the active tool view. Instead, each
tool view should center its content column within the available width:

```swift
// In each tool view's ScrollView content:
.frame(maxWidth: .infinity)  // fill available width
// Inside that, the VStack:
.frame(maxWidth: HubToolLayout.maxContentWidth, alignment: .topLeading)
.frame(maxWidth: .infinity)  // center the constrained column
```

#### 4.3 Collapsed rail

The collapsed sidebar rail (the 32px button) should use a subtle hover state:

```swift
.onHover { hovering in
    // animate background to Colors.accentTint on hover
}
```

#### 4.4 Window chrome

Keep the toolbar sidebar toggle buttons but ensure they use SF Symbols with the
`.hierarchical` rendering mode for consistency.

#### 4.5 Minimum window size

```swift
.defaultSize(width: 1_280, height: 820)  // was 1_420 x 860 -- slightly smaller default
```

---

## 5. Tool Sidebar Redesign

### File: `Sources/NikoMusicHub/AppShell/ToolSidebarView.swift`

#### 5.1 App identity header

Current: Logo + "Niko Music Hub" + "Local tools" in a horizontal stack.

New:
```
[Logo 26x26]  Niko Music Hub
               v1.0
```
- Logo size: 26x26 (was 30x30) -- less dominant
- App name: size 14, weight .semibold, design .rounded (was 15)
- Version: size 10, weight .medium, foregroundStyle .tertiary
- Remove "Local tools" subtitle -- it's meaningless to the user
- Padding: top 14, bottom 8 (was top 18, bottom 10)

#### 5.2 Section label

"TOOLS" label: keep the uppercased caption style but change:
- foregroundStyle: `.quaternary` (was `.tertiary`) -- even more subtle
- padding bottom: 2 (was 4)

#### 5.3 Tool rows

Each sidebar row changes from icon-only to icon + label with consistent sizing:

```
[icon 18x18]  [12px gap]  Tool Name
```

- Icon: SF Symbol in `.hierarchical` mode, frame 18x18
- Label: size 13, weight .medium (selected: .semibold)
- Row padding: horizontal 10, vertical 8 (was horizontal 12, vertical 9)
- Row height: consistent 36px across all items
- Selected row: `HubDesignSystem.Colors.accentTint` fill with
  `HubDesignSystem.Colors.selectedStroke` border, cornerRadius `.row`
- Selected label color: `HubDesignSystem.Colors.accent` (not raw `.accentColor`)
- Unselected label color: `.primary` (not `.secondary`)

#### 5.4 Health strip

The `HelperToolsHealthStrip` at the bottom of the sidebar:
- Keep the glass card wrapping
- Change the status dots to use `HubDesignSystem.Size.statusDot` (7px)
- Label "Helper Tools" with size 10, weight .semibold, foregroundStyle .tertiary
- Each tool line: `[dot] [tool name] [status]` with size 10
- Reduce card padding: 10 (was 12)
- Reduce outer padding: horizontal 8, bottom 10 (was horizontal 10, bottom 14)

---

## 6. Output Inbox Redesign

### File: `Sources/NikoMusicHub/AppShell/OutputInboxInspectorView.swift`

#### 6.1 Header

Current: "Output Inbox" as a section title, then "Output folder" label, path, and a
folder button.

New:
```
Output                                    [folder icon button]
~/Music/Niko Music Hub/Inbox
```
- Title: "Output" (not "Output Inbox" -- shorter)
- Size: 14, weight .semibold, design .rounded
- Folder path: size 10, truncationMode .middle, foregroundStyle .tertiary
- Folder-choose button: move to same line as title, right-aligned
- Remove the separate "Output folder" label -- redundant

#### 6.2 Empty state

Current: "No outputs saved yet" + description text.

New: Center vertically in available space:
```
        [arrow.down.to.line icon, size 24, .quaternary]
        No outputs yet
        Converted files, recordings, and
        downloads appear here.
```
- Icon: size 24, foregroundStyle .quaternary
- Title: size 13, weight .semibold
- Body: size 11, foregroundStyle .secondary, multilineTextAlignment .center

#### 6.3 Output item cards

Current: VStack with filename (size 13 semibold), status text, and a folder button.

New -- each card in a horizontal layout:
```
[file-type icon]  filename.wav                [drag grip]
                  status text
```
- File-type icon: derive from extension -- `waveform` for .wav, `film` for .mp4,
  `doc` for others. Size 14, frame 22x22, foregroundStyle .secondary
- Filename: size 12, weight .medium, lineLimit 1
- Status: size 10, foregroundStyle based on status
- Drag grip: only show on hover (not always visible)
- Card padding: 10 (was 12)
- Card corner radius: `.row` (8px)
- Remove the "Reveal in Finder" button from inside the card -- add a context menu
  (right-click) instead with "Reveal in Finder" and "Open" options
- Single-click on the card: reveal in Finder
- Card spacing: `Spacing.cardGap` (8px)

#### 6.4 Divider

Remove `Divider().opacity(0.4)` between folder path and items list. Use spacing alone
(`Spacing.section` = 24px gap).

---

## 7. Archive Browser Redesign

This is the most complex page. Multiple files involved.

### 7.1 Archive Sidebar (`ArchiveSidebarView.swift`)

#### Toolbar row

Current: `Archive` label + scan button + ellipsis menu.

New:
```
Archive   [99 songs]                [scan] [+]
```
- "Archive" in size 15, weight .semibold, design .rounded
- Song count badge: size 10, weight .medium, foregroundStyle .tertiary,
  background `.quaternary`, cornerRadius .chip, padding horizontal 6 vertical 2
- Scan button: `HubIconButton` (icon-only is OK here -- contextually obvious)
- `+` button: opens the current ellipsis menu content directly
- Remove the ellipsis `Menu` wrapper -- it adds a click to every action

#### Roots section

Keep the `DisclosureGroup` but:
- Collapse by default when there is exactly 1 root (already done)
- Root count label: "1 root" / "2 roots" -- keep current style

#### Shelf picker (All Songs / Recently Bounced / etc.)

Current: macOS segmented picker that overflows horizontally.

New: Horizontal scroll of compact chips:
```
[All]  [Recent]  [Bounced]  [Stems]  [Collabs]
```
- Each chip: `HubCompactChipColors`, height 26, cornerRadius .chip,
  padding horizontal 10
- Selected chip: filled with `HubDesignSystem.Colors.accent`, white text
- Unselected chip: `Color.primary.opacity(0.06)` fill, `.secondary` text
- Chips scroll horizontally if they overflow (use `ScrollView(.horizontal)`)
- Remove the separate `shelfPicker` and `browseControls` -- merge into one
  chip strip

#### Sort picker

Current: segmented picker (`Recent CPR` / `Title A-Z`).

New: integrate into the chip strip as a dropdown:
- Single chip labeled with current sort (e.g., "Title A-Z") with a
  chevron.down indicator
- Tap opens a `Menu` with sort options
- This saves vertical space

#### Search field

Keep the current pill-shaped search field. Changes:
- Remove the leading `magnifyingglass` icon from the HStack -- use
  `.searchable` or at minimum put the icon inside the TextField
  as a prompt
- Increase height to 34px (was ~30)
- Font size 13 (already correct)

#### Song cards (`SongCardView.swift`)

Current: VStack with title (15 semibold), match summary, warning, mini-player.

New -- tighter, more scannable:
```
Song Title Here                              [warning icon]
subtitle text or match info
[play] ---- waveform minibar ---- [0:42]
```
- Title: size 14, weight .semibold (was 15 -- too big for a list item)
- Subtitle: size 10, foregroundStyle .secondary
- Warning icon: small orange `exclamationmark.triangle` instead of text
- Mini-player: compact horizontal bar (keep current `.compact` style)
- Card padding: 10 (was 12) -- tighter cards for better density
- Selected card: `selected: true` on `hubGlassCard` -- keep existing
  behavior but use new color tokens
- Card spacing: 6px (was 10px) -- tighter list

### 7.2 Song Detail View (`SongDetailView.swift`)

This view needs the most dramatic restructuring. Currently it's an endless
scroll with no visual sections.

#### New structure: grouped sections with clear dividers

```
SECTION 1: HERO
[Song Title]                                      [22pt semibold]
Folder: original-folder-name                      [11pt tertiary]

SECTION 2: METADATA (glass card)
Display title     [text field                               ]
Aliases           [text field                               ]
Note              [text area                                ]

SECTION 3: PREVIEW (glass card)
Main preview                                       [Auto/Manual badge]
[=== WAVEFORM HERO ========================================]
[-5s]  [PLAY]  [+5s]            filename.wav      0:42/3:15

SECTION 4: ACTIONS (inline row, no card)
[Open in Cubase]  [Reveal in Finder]  [Save Metadata]
P preview   O Cubase   F Finder   D detail         [10pt tertiary]

SECTION 5: DETAILS (glass card, disclosure group -- collapsed by default)
Collaborators     [toggle list]
CPR Versions      [list with Main/Hidden badges]
Mixdown BPM       128.5 (high confidence)
Preview Candidates [mini-player list]

SECTION 6: FOOTER (inline, no card)
[  ] Hide song from browse
```

Key changes:
- **Group metadata fields into a single card** instead of loose VStacks
- **Move collaborators, CPR list, and preview candidates into a collapsible
  "Details" section** -- most users don't need these on every visit
- **Make action buttons labeled**: "Open in Cubase" not just a piano icon
- **Action button sizing**: all use `.bordered` style, same height
  Primary action (Open in Cubase): `.borderedProminent`
- **Section spacing**: 24px between sections
- **Section titles**: size 13, weight .semibold, foregroundStyle .secondary
- **Remove the `Stems detected` and `Sidecar notes` inline text** -- move
  into the Details disclosure group

#### Waveform hero controls (`ArchiveWaveformHeroView.swift`)

Current: `-5s` and `+5s` as text buttons, play as icon button.

New:
```
[backward.5]  [PLAY/PAUSE]  [forward.5]     filename     0:42/3:15
```
- Use SF Symbols: `gobackward.5` and `goforward.5`
- All three buttons: `.bordered` style, same size
- Play button: `.borderedProminent` with accent tint
- Filename and time: right-aligned, size 11

### 7.3 Archive First Run (`ArchiveFirstRunView.swift`)

Current: Left-aligned card with title, description, and an icon button.

New: Centered modal with more visual warmth:
```
                 [music.note.house icon, 36pt]

           Welcome to your Cubase archive

    Choose the folder that contains your song
    projects. The hub scans read-only -- your
    files on disk are never renamed or moved.

              [Choose Folder]  (prominent button with label)
```
- Center the card in the overlay
- Icon: size 36, foregroundStyle gradient from accent to accentDeep
- Title: size 20, weight .semibold (was 24 -- less aggressive)
- Body: size 13, centered, foregroundStyle .secondary
- Button: labeled "Choose Folder", `.borderedProminent`, controlSize .large
- Card max width: 420 (was 480)

### 7.4 Mini Player (`ArchiveMiniPlayerView.swift`)

Keep the current design but:
- Play button tint: `HubDesignSystem.Colors.accent` (not `ArchiveDesignTokens.accent`)
- Slider: ensure `.controlSize(.mini)` for compact, `.small` for full
- Time label: use `Typography.micro()` font
- Hook marker: use `Colors.accent.opacity(0.85)` -- keep existing

### 7.5 New Song Sheet (`NewSongSheet.swift`)

Current: VStack with text fields and buttons.

New:
- Title: "New Song Draft" (size 16 semibold, was 18)
- Reduce sheet width to 360 (was 380)
- Group name + note fields into a single card
- "Create Draft" button: labeled, `.borderedProminent`
- "Cancel" button: `.bordered`
- Both buttons: same height, right-aligned row with `Spacer` between

### 7.6 Files to delete

- `ArchiveDesignTokens.swift` -- replaced by `HubDesignSystem.Colors`
- `HubCompactChipColors+Archive.swift` -- merge into `HubCompactChipColors.swift`
  as a single `.archive` static property using the new accent tokens

---

## 8. BPM Tapper Redesign

### File: `Sources/FeatureBPMTapper/BPMTapperView.swift`

#### 8.1 Layout restructuring

Current: header, tapWorkflow (bpmReadout + adjustmentPicker + tapSurface + actionRow),
historySection. All left-aligned, maxWidth 560.

New: Center the entire workflow. The BPM Tapper is a focused, single-purpose tool.

```
                        BPM Tapper
                   Tap the pad or press Space

                          --
                          BPM
                        0 taps

          [Original]  [Half-Time]  [Double-Time]

     +--------------------------------------------+
     |                                            |
     |              Tap Tempo                     |
     |         Tap the pad or press Space         |
     |                                            |
     +--------------------------------------------+

          [Copy BPM]  [Save BPM]  [Reset]

     ____________________________________________

                    Recent Tempos

     [125 BPM  11:49 - Original from 125]  [copy]
```

#### 8.2 BPM readout

- Size: `Typography.display()` = 56pt bold rounded (was 40pt semibold)
- Alignment: center (was leading)
- "BPM" suffix: size 14, foregroundStyle .tertiary (was 12, .secondary)
- Tap count: size 12, foregroundStyle .tertiary, centered

#### 8.3 Tap surface

- Min height: 240 (was 180) -- much bigger target
- Max width: 560 (was 440)
- Center text: "Tap Tempo" size 18, weight .semibold (was 16)
- Subtitle: remove duplicate status text -- just show "Tap or press Space"
- Focus ring: 2px accent when focused (keep existing)
- Add a subtle scale animation on tap: `.scaleEffect(0.98)` for 100ms

#### 8.4 Action buttons -- LABELED

```swift
HStack(spacing: Spacing.controlGap) {
    HubLabeledButton(icon: "doc.on.doc", label: "Copy BPM", style: .secondary)
    HubLabeledButton(icon: "bookmark.fill", label: "Save BPM", style: .primary)
    HubLabeledButton(icon: "arrow.counterclockwise", label: "Reset", style: .secondary)
}
```
(See `HubLabeledButton` in Section 13.)

#### 8.5 History section

- Add `Divider()` with `Colors.separator` between workflow and history
- History card: keep current design but use new accent tokens
- "Clear History" button: labeled "Clear History" with trash icon, `.destructive` role

---

## 9. WAV Converter Redesign

### File: `Sources/FeatureAudioConverter/AudioConverterView.swift`

#### 9.1 Drop zone

Current: thin border, text-heavy.

New:
```
+--------------------------------------------------+
|                                                  |
|      [arrow.down.doc icon, 28pt, .tertiary]      |
|                                                  |
|         Drop audio files to convert              |
|   M4A, MP3, WAV, AIFF, or FLAC accepted         |
|                                                  |
|            [Choose Files]                        |
|                                                  |
+--------------------------------------------------+
```
- Border: 1.5px dashed stroke using `StrokeStyle(lineWidth: 1.5, dash: [6, 4])`
- Border color: `Colors.separator` (normal), `Colors.accent` (drop targeted)
- Background: `Color.primary.opacity(0.02)` (normal),
  `Colors.accentTint` (drop targeted)
- Icon: size 28, foregroundStyle .quaternary
- Title: size 15, weight .semibold (was 16)
- Subtitle: size 12, foregroundStyle .secondary
- Button: labeled "Choose Files" with `plus` icon, `.bordered`
- Min height: 180 (was 160)

#### 9.2 Preset strip

Current: horizontal text line with a tiny settings button.

New: always-visible mini-form:
```
[waveform icon]  44.1 kHz  |  24-bit  |  Stereo     [Edit Preset]
```
- Use `|` text dividers between values, not a single comma-separated string
- Each value: size 13, monospacedDigit
- "Edit Preset" button: labeled, `.bordered`, toggles the detail pickers
- Card padding: 10

#### 9.3 Action row -- LABELED

```swift
HStack(spacing: Spacing.controlGap) {
    HubLabeledButton(icon: "plus", label: "Add Files", style: .secondary)
    HubLabeledButton(icon: "waveform.badge.plus", label: "Convert", style: .primary)
    HubLabeledButton(icon: "stop.fill", label: "Stop", style: .secondary, isEnabled: ...)
}
```

#### 9.4 Batch rows

Keep the current horizontal layout but:
- Status dot: 7px (was 8px)
- Source filename: size 13 semibold (keep)
- Source type badge: use a capsule pill background
  `Text("M4A").font(.micro()).padding(.horizontal, 6).padding(.vertical, 2)
  .background(Colors.accent.opacity(0.1)).clipShape(Capsule())`
- Progress bar: tint with `Colors.accent` (not raw `.accentColor`)
- Reveal button: only show when state is `.verified` (already correct)
- Converter badge ("FFmpeg" / "Native"): move to same line as source type

---

## 10. Audio Recorder Redesign

### File: `Sources/FeatureAudioRecorder/AudioRecorderView.swift`

#### 10.1 Layout -- centered, hero-focused

The recorder should be the most dramatic page. The timer is the hero.

```
                    Audio Recorder
                     Ready to record

        Recording Sonntag, 31. Mai 2026.wav

                    00:00:00              [56pt mono bold]

        [================ METER ================]

              [Record]  or  [Stop]        [labeled button]

        Max Duration
        [5 min] [10 min] [15 min] [30 min] [60 min] [Unlimited]
```

#### 10.2 Timer display

- Font: `Typography.display()` = 56pt bold rounded (was 32pt medium monospaced)
- Use `.monospacedDigit()` modifier
- Color: `.primary` when recording, `.tertiary` when idle (was `.secondary`)
- Center-aligned

#### 10.3 Meter bar

Current: raw rectangle, no polish.

New:
- Height: 8px (was 12px) -- thinner is more refined
- CornerRadius: 4px (full rounded caps)
- Background: `Color.primary.opacity(0.06)`
- Fill: gradient from `Colors.success` to `Colors.warning` to `Colors.danger`
  based on peak level
- Add a subtle glow shadow when recording:
  `.shadow(color: Colors.success.opacity(0.3), radius: 4)`

#### 10.4 Record/Stop button

Current: stock `.bordered` button with label text. Actually decent -- keep the
labeled approach but make it more prominent:
- Idle: "Record" with `record.circle` icon, `.borderedProminent`, tint `.red`
- Recording: "Stop" with `stop.fill` icon, `.borderedProminent`, tint `.red`
- Size: `.controlSize(.large)` -- this is THE primary action
- Animate the recording indicator dot INTO the button (red pulsing circle
  as a leading icon) instead of as a separate element

#### 10.5 Max Duration picker

Keep the segmented picker but:
- Use `Picker` with `.segmented` style (already correct)
- Move the "Max Duration" label above the picker, not next to it
- Add spacing of 24px between the record button area and this section

#### 10.6 Save confirmation

Current: HStack with green text and icon buttons.

New: a brief toast-style banner at the top of the page:
```
[checkmark.circle.fill]  Recording saved  [Reveal]  [Open]
```
- Background: `Colors.success.opacity(0.12)`
- cornerRadius: `.row`
- Auto-dismiss after 5 seconds

---

## 11. Downloader Redesign

### File: `Sources/FeatureDownloader/DownloaderView.swift`

#### 11.1 URL input

Current: stock `.roundedBorder` TextField.

New: custom styled field that matches the glass aesthetic:
```
[link icon]  Paste a supported URL...            [Download] [Clear]
```
- Field: remove `.roundedBorder`, wrap in a `hubGlassCard` with `.row` radius
- Leading icon: `link` SF Symbol, size 13, foregroundStyle .tertiary
- Padding: horizontal 12, vertical 10
- Buttons: move download and clear to trailing edge of the field, inline
- Download button: labeled "Download", `.borderedProminent`, accent tint
- Clear button: icon-only `xmark.circle.fill`, `.plain` style, `.tertiary` color

#### 11.2 Format selection

Current: glass card with two pickers.

New: horizontal chip strip (similar to Archive shelf picker):
```
Download as:  [Audio only]  [Video + Audio]    Format:  [WAV]
```
- Media kind: two chips, mutually exclusive toggle
- Format: single chip with dropdown (changes based on media kind)
- Remove the "Download as" card wrapper -- put inline

#### 11.3 Trust info card

Current: four lines of small gray text.

New: collapsible detail (shown by default when ready to download):
```
[shield.lefthalf.filled icon]  Download details
Source:   youtube.com/watch?v=...
Format:   Audio only - WAV
Output:   ~/Music/Niko Music Hub/Inbox
Only downloads from the URL you entered.
```
- Icon: `shield.lefthalf.filled`, foregroundStyle `Colors.accent`
- Use `LabeledContent` for Source/Format/Output rows
- Trust notice: size 10, italic, foregroundStyle .tertiary

#### 11.4 Action buttons -- already inline in the new URL field design

See 11.1 above. The download button is part of the URL input row.

#### 11.5 Progress and log

Keep current design but:
- Progress bar: tint `Colors.accent`
- Log area: use `Typography.mono(size: 10)` for log entries
- Log card: `.row` radius (was `.row` -- keep)
- Max height: 140 (was 160) -- less screen real estate for logs

---

## 12. Settings Redesign

### File: `Sources/NikoMusicHub/Settings/SettingsView.swift`

#### 12.1 Overall layout

Current: left-aligned scroll with `SettingsSection` cards.

New: centered, two-column layout for wider screens:

For narrow windows (< 800px center panel): single column, current layout.
For wide windows: settings form centered, max width 640.

#### 12.2 Section hierarchy

Add visual hierarchy between section types:

**Critical sections** (General, Output, Cubase Archive): normal card style
**Configuration sections** (Audio Conversion, Recording): slightly muted card
**Information sections** (Privacy, Helper Tools, About): no card wrapper,
  just indented content with a section title

#### 12.3 Settings header

Current: icon label + description text.

New: simpler, integrated with the page:
```
Settings
Hub-wide preferences for startup, output, and tools.
```
- Title: `Typography.screenTitle()` (18pt semibold rounded)
- Subtitle: size 12, foregroundStyle .secondary
- Remove the `gearshape` icon from the title -- it's redundant since the
  sidebar already shows the gear icon for the Settings tab

#### 12.4 Archive roots section -- LABELED actions

Current: `HubIconButton` with `folder.badge.plus` icon and `trash` icons.

New:
- Add root button: labeled "Add Root" with `folder.badge.plus` icon,
  `.bordered` style
- Remove root button: labeled "Remove" (or keep icon-only `trash` since
  the context is clear from the row), `.plain` style, `.destructive` role
- Root rows: add a `folder.fill` icon (already present in sidebar version)

#### 12.5 Helper tools section

Current: three identical rows with `folder` icon buttons.

New: use `LabeledContent` with inline status:
```
FFmpeg      Auto-detect                    [Choose...]
ffprobe     Auto-detect                    [Choose...]
yt-dlp      /opt/homebrew/bin/yt-dlp       [Choose...] [Clear]
```
- "Choose..." button: labeled, `.bordered`, controlSize .small
- "Clear" button: only shown when a custom path is set, icon-only `xmark`

#### 12.6 `SettingsSection` component

Current inner card padding: 14. Reduce to 12.
Add optional `importance` parameter: `.high` (normal card),
`.medium` (muted card), `.low` (no card, just indented).

---

## 13. Shared Component Library

### 13.1 New component: `HubLabeledButton`

**File: `Sources/AppCore/Components/HubLabeledButton.swift`** (NEW)

This replaces most uses of `HubIconButton` for primary and secondary actions.

```swift
public struct HubLabeledButton: View {
    let icon: String
    let label: String
    let style: HubLabeledButtonStyle
    var role: ButtonRole? = nil
    var isEnabled: Bool = true
    let action: () -> Void

    public enum HubLabeledButtonStyle {
        case primary    // .borderedProminent
        case secondary  // .bordered
        case ghost      // .plain with hover background
    }

    public var body: some View {
        Button(role: role, action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(buttonStyle)
        .controlSize(.small)
        .disabled(!isEnabled)
    }
}
```

### 13.2 Updated component: `HubIconButton`

Keep `HubIconButton` for truly icon-only cases:
- Sidebar collapse/expand rails
- Inline row actions where context is unambiguous (trash next to a named item)
- Close buttons
- Actions inside compact cards

Changes to `HubIconButton`:
- Icon frame: 30x30 (was 28x28)
- Font size: 14 (was 13) for `.toolbar`, 13 (was 12) for `.compactChip`
- Add hover state: background transitions to `Colors.accentTint` on hover

### 13.3 Updated component: `StatusDot`

- Size: 7px (was 8px)
- Colors: use `HubDesignSystem.Colors` tokens:
  - `.queued`: `.secondary`
  - `.running`: `Colors.accent` (was `.green` -- the accent is the active color)
  - `.completed`: `Colors.success`
  - `.failed`: `Colors.danger`
  - `.canceled`: `Colors.warning`

### 13.4 Updated component: `StandardErrorCard`

- Label icon + text: use `Colors.warning` for permission/URL errors,
  `Colors.danger` for tool/file errors (keep current logic)
- Recovery buttons: use `HubLabeledButton` instead of raw `Button`
- Card padding: 14 (keep)
- Ensure `.fixedSize(horizontal: false, vertical: true)` on body text

### 13.5 Updated component: `HubToolLayout`

```swift
public enum HubToolLayout {
    public static let horizontalPadding: CGFloat = 24  // keep
    public static let bottomPadding: CGFloat = 24      // keep
    public static let topPadding: CGFloat = 16         // was 20 -- tighter
    public static let sectionSpacing: CGFloat = 24     // keep
    public static let maxContentWidth: CGFloat = 680   // was 720 -- slightly narrower
}
```

### 13.6 New component: `HubSectionDivider`

**File: `Sources/AppCore/Components/HubSectionDivider.swift`** (NEW)

```swift
public struct HubSectionDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(HubDesignSystem.Colors.separator)
            .frame(height: 1)
            .padding(.vertical, 4)
    }
}
```

Use this between major sections instead of `Divider().opacity(0.4)`.

---

## 14. Implementation Order

Execute in this exact order to avoid breaking changes:

### Wave 1: Design System Foundation (no visible changes yet)
1. Update `HubDesignSystem.swift` with new tokens
2. Update `HubGlassChrome.swift` with refined glass parameters
3. Create `HubLabeledButton.swift`
4. Create `HubSectionDivider.swift`
5. Update `HubIconButton.swift` (size + hover)
6. Update `StatusDot.swift` (size + colors)
7. Update `HubToolLayout.swift` (spacing tweaks)
8. Update `HubCompactChipColors.swift` (merge archive extension)

### Wave 2: Shell & Navigation
9. Update `AppShellView.swift` (spacing, centering)
10. Update `ToolSidebarView.swift` (row sizing, labels, header)
11. Update `OutputInboxInspectorView.swift` (header, empty state, cards)
12. Delete `ArchiveDesignTokens.swift` and update all 16 references

### Wave 3: Tool Pages (one at a time)
13. Update `BPMTapperView.swift` (center layout, display font, labeled buttons)
14. Update `AudioRecorderView.swift` (hero timer, meter, labeled button)
15. Update `AudioConverterView.swift` (drop zone, preset strip, labeled buttons)
16. Update `DownloaderView.swift` (URL field, format chips, labeled button)
17. Update `SettingsView.swift` (hierarchy, labeled buttons, helper tools)

### Wave 4: Archive Browser (most complex)
18. Update `ArchiveSidebarView.swift` (toolbar, shelf chips, sort, search)
19. Update `SongCardView.swift` (tighter cards, warning icon)
20. Update `SongDetailView.swift` (grouped sections, labeled actions, disclosure)
21. Update `ArchiveWaveformHeroView.swift` (SF Symbol seek buttons)
22. Update `ArchiveFirstRunView.swift` (centered modal)
23. Update `ArchiveMiniPlayerView.swift` (accent tokens)
24. Update `NewSongSheet.swift` (smaller, grouped)
25. Update `ArchiveCollaboratorAddressBookView.swift` (accent tokens)
26. Update `ArchiveIntelligencePanelView.swift` (accent tokens)
27. Update `ArchiveDiagnosticsPanelView.swift` (accent tokens)
28. Update `ArchiveHealthReportView.swift` (accent tokens)
29. Update `ArchiveSidebarMorePanel.swift` (accent tokens)
30. Update `RootSelectionView.swift` (accent tokens, labeled buttons)
31. Delete `HubCompactChipColors+Archive.swift`

### Wave 5: Polish
32. Update `StandardErrorCard.swift` (labeled recovery buttons)
33. Update `ToolHeaderBlock.swift` (use Typography tokens)
34. Update `NikoMusicHubApp.swift` (default window size)
35. Full visual regression test of every page

---

## 15. File Manifest

### Files to CREATE (2)
| Path | Purpose |
|------|---------|
| `Sources/AppCore/Components/HubLabeledButton.swift` | Labeled action button component |
| `Sources/AppCore/Components/HubSectionDivider.swift` | Subtle section divider |

### Files to DELETE (2)
| Path | Reason |
|------|--------|
| `Sources/FeatureArchiveBrowser/ArchiveDesignTokens.swift` | Replaced by `HubDesignSystem.Colors` |
| `Sources/FeatureArchiveBrowser/HubCompactChipColors+Archive.swift` | Merged into `HubCompactChipColors.swift` |

### Files to MODIFY (33)
| Path | Scope of change |
|------|-----------------|
| `Sources/AppCore/Components/HubDesignSystem.swift` | Full rewrite -- new tokens |
| `Sources/AppCore/Components/HubGlassChrome.swift` | Shadow, gradient, highlight tweaks |
| `Sources/AppCore/Components/HubIconButton.swift` | Size increase, hover state |
| `Sources/AppCore/Components/HubToolLayout.swift` | Spacing/padding tweaks |
| `Sources/AppCore/Components/StatusDot.swift` | Size + color token update |
| `Sources/AppCore/Components/HubCompactChipColors.swift` | Add `.archive` variant |
| `Sources/AppCore/Components/HubDragAffordance.swift` | Show only on hover |
| `Sources/AppCore/Components/ToolHeaderBlock.swift` | Use Typography tokens |
| `Sources/AppCore/Errors/StandardErrorCard.swift` | Labeled recovery buttons |
| `Sources/NikoMusicHub/NikoMusicHubApp.swift` | Default window size |
| `Sources/NikoMusicHub/AppShell/AppShellView.swift` | Panel spacing, centering |
| `Sources/NikoMusicHub/AppShell/ToolSidebarView.swift` | Row sizing, header, health strip |
| `Sources/NikoMusicHub/AppShell/OutputInboxInspectorView.swift` | Full redesign |
| `Sources/NikoMusicHub/Settings/SettingsView.swift` | Section hierarchy, labeled buttons |
| `Sources/FeatureBPMTapper/BPMTapperView.swift` | Center layout, hero font, labeled buttons |
| `Sources/FeatureAudioConverter/AudioConverterView.swift` | Drop zone, preset strip, labels |
| `Sources/FeatureAudioRecorder/AudioRecorderView.swift` | Hero timer, meter, labeled button |
| `Sources/FeatureDownloader/DownloaderView.swift` | URL field, format chips, label |
| `Sources/FeatureArchiveBrowser/ArchiveBrowserView.swift` | Token migration |
| `Sources/FeatureArchiveBrowser/ArchiveSidebarView.swift` | Toolbar, chips, search |
| `Sources/FeatureArchiveBrowser/SongCardView.swift` | Tighter cards, warning icon |
| `Sources/FeatureArchiveBrowser/SongDetailView.swift` | Grouped sections, disclosure |
| `Sources/FeatureArchiveBrowser/ArchiveWaveformHeroView.swift` | SF Symbol seek buttons |
| `Sources/FeatureArchiveBrowser/ArchiveFirstRunView.swift` | Centered modal |
| `Sources/FeatureArchiveBrowser/ArchiveMiniPlayerView.swift` | Accent token migration |
| `Sources/FeatureArchiveBrowser/NewSongSheet.swift` | Smaller, grouped |
| `Sources/FeatureArchiveBrowser/ArchiveCollaboratorAddressBookView.swift` | Token migration |
| `Sources/FeatureArchiveBrowser/ArchiveIntelligencePanelView.swift` | Token migration |
| `Sources/FeatureArchiveBrowser/ArchiveDiagnosticsPanelView.swift` | Token migration |
| `Sources/FeatureArchiveBrowser/ArchiveHealthReportView.swift` | Token migration |
| `Sources/FeatureArchiveBrowser/ArchiveSidebarMorePanel.swift` | Token migration |
| `Sources/FeatureArchiveBrowser/RootSelectionView.swift` | Token migration, labeled buttons |
| `Sources/FeatureArchiveBrowser/ArchiveWaveformView.swift` | Token migration |

---

## Appendix A: Color Palette Reference

```
Accent (primary):       #5A6BF2  (HSL 232, 85%, 65%)
Accent tint:            #5A6BF2 @ 12% opacity
Accent deep (pressed):  #4757D1  (HSL 232, 60%, 55%)
Success:                #4DC87A  (HSL 145, 55%, 48%)
Warning:                #F2AD40  (HSL 38, 88%, 60%)
Danger:                 #EB5757  (HSL 0, 78%, 63%)
Separator:              primary @ 8% opacity
Card stroke:            primary @ 7% opacity
Selected stroke:        accent @ 35% opacity
```

## Appendix B: Typography Scale Reference

```
Display:        56pt  bold      rounded    (BPM, timer)
Screen title:   18pt  semibold  rounded    (page headers)
Section title:  14pt  semibold  rounded    (within page)
Body:           13pt  regular   default    (primary text)
Body small:     12pt  regular   default    (secondary text)
Caption:        11pt  medium    default    (labels, footers)
Micro:          10pt  medium    default    (badges, dots)
Mono:           var   medium    monospaced (timers, logs)
```

## Appendix C: Spacing Scale Reference

```
Shell gap:      10px  (between panels)
Panel padding:  16px  (inside panels)
Section gap:    24px  (between sections)
Card gap:       8px   (between cards in a list)
Control gap:    8px   (between buttons in a row)
Inline gap:     6px   (between icon and label)
```

## Appendix D: Corner Radius Scale Reference

```
Shell:    14px
Panel:    12px
Card:     10px
Row:       8px
Button:    8px
Chip:      6px
Pill:     18px
```
