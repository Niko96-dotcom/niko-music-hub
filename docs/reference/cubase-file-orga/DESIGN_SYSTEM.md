# Design System — Editorial Sonic Archive

## Direction
Dark, soft, rounded, spacious, premium, musical. Inspired by shadcn/ui Maia temperament.
NOT: spreadsheet, Finder, dashboard SaaS, DAW clone, enterprise.
Waveform is the hero visual element. No generic file icons ever.

## Color Tokens (Tailwind + CSS custom properties)

### Base palette
- `--color-bg`:           #0A0A0C (near-black, slightly cool)
- `--color-surface`:      #141418 (cards, panels)
- `--color-surface-hover`: #1C1C22 (card hover, interactive surfaces)
- `--color-surface-elevated`: #1E1E24 (modals, popovers)
- `--color-border`:       #2A2A32 (subtle borders)
- `--color-border-focus`:  #4A4A58 (focus rings)

### Text
- `--color-text-primary`:   #F0F0F2 (titles, primary content)
- `--color-text-secondary`: #A0A0AC (metadata, labels)
- `--color-text-muted`:     #6A6A78 (disabled, tertiary)

### Accent
- `--color-accent`:        #8B7BF4 (muted lavender — primary interactive)
- `--color-accent-hover`:  #9D8FF6
- `--color-accent-muted`:  rgba(139, 123, 244, 0.15) (badge backgrounds)

### Semantic
- `--color-success`:       #4ADE80
- `--color-warning`:       #FBBF24
- `--color-error`:         #F87171

### Waveform
- `--color-waveform`:        #6A6A78 (idle)
- `--color-waveform-active`: #8B7BF4 (playing, progress)
- `--color-waveform-hover`:  #9D8FF6

## Typography
Font stack: `'Inter', system-ui, -apple-system, sans-serif`

| Token | Size | Weight | Line Height | Tracking | Use |
|-------|------|--------|-------------|----------|-----|
| `display` | 28px | 600 | 1.2 | -0.02em | Page titles |
| `title` | 20px | 600 | 1.3 | -0.01em | Section headers |
| `heading` | 16px | 600 | 1.4 | -0.01em | Card titles |
| `body` | 14px | 400 | 1.5 | 0 | Default text |
| `body-medium` | 14px | 500 | 1.5 | 0 | Labels, emphasis |
| `caption` | 12px | 400 | 1.4 | 0.01em | Metadata, timestamps |
| `mono` | 13px | 400 | 1.4 | 0 | File paths, technical |

## Spacing Scale
| Token | Value |
|-------|-------|
| `xs` | 4px |
| `sm` | 8px |
| `md` | 16px |
| `lg` | 24px |
| `xl` | 32px |
| `2xl` | 48px |
| `3xl` | 64px |

## Radii
| Token | Value |
|-------|-------|
| `sm` | 4px |
| `md` | 8px |
| `lg` | 12px |
| `xl` | 16px |
| `full` | 9999px |

## Shadows
Minimal. Only for elevated surfaces.
- `shadow-card`: `0 1px 3px rgba(0,0,0,0.4)`
- `shadow-elevated`: `0 4px 16px rgba(0,0,0,0.5)`

## Components

### SongCard
- Surface background with `radii.lg` corners
- Waveform hero area (clickable → play)
- Title below waveform (clickable → detail page)
- Collaborator badges (pills, accent-muted bg, caption text)
- Metadata chips: version count, stems indicator, bounce recency
- Hover: surface-hover bg, subtle scale or glow on waveform
- Min width: 240px. Generous padding (spacing.md).

### Waveform
- Canvas or SVG rendered
- Full width of container
- Height: 64px on cards, 120px on detail page
- Idle: waveform color. Playing: progressive fill with waveform-active
- Clickable for seek. Cursor indicates playback position.

### Button
- Primary: accent bg, white text, radii.md, 36px height min
- Secondary: transparent bg, border, text-secondary, radii.md
- Ghost: no border, text-secondary, hover surface-hover
- All: 14px body-medium, horizontal padding spacing.md

### Badge / Pill
- accent-muted bg, accent text, radii.full, caption text
- Padding: xs vertical, sm horizontal

### SectionHeader
- title typography, text-primary
- Optional "See All" link in text-secondary
- Bottom margin spacing.lg

### Input / Search
- surface bg, border, radii.md
- body text, text-secondary placeholder
- Focus: border-focus ring
- Height: 40px

### Sidebar
- Fixed left, width 240px
- bg color, right border
- Navigation items: body-medium, text-secondary, hover text-primary + surface-hover bg
- Active item: text-primary + accent-muted bg
