# End-phase triage — 29 preserved (NMH-098…126)

Date: 2026-09-17 (Europe/Berlin)
Tip context: integration worktree after daytime final5 Accept
Source class (FIX-SPECS): every row is `[— · passes tested check]`

## Bottom line

These are **not open bugs**. The overnight deferred-sweep parked them as end-phase regression / wrap-up checks after related sev1–7 work landed. Triage outcome:

| Bucket | Count | Meaning |
|--------|------:|---------|
| A — verify → likely `verified-no-change` | 27 | Code already matches Accept; promote after spot-check |
| B — verify with gated caveat | 1 | NMH-122: Friends+backup removal still gated; rest of vault fail-closed can promote |
| C — needs new product fix | 0 | None found in this pass |

**No “start coding a missing feature” batch.** Next work is verify-in-batches, then ledger promote. Only reopen to `in-progress` / code if a verify finds a regression.

## Full inventory

| ID | Title | Related (all fixed unless noted) | Triage |
|----|-------|----------------------------------|--------|
| 098 | About + Check for Updates App-menu order | 001 fixed | A — code: About @ appInfo, Updates after appSettings |
| 099 | Settings apply immediately; helper path validate | 015/071 fixed; 102 preserved (peer) | A |
| 100 | ToolPaneCache + a11yHidden inactive panes | 011/017 fixed; 116 peer | A |
| 101 | Restore will not overwrite | 053 fixed | A — highest-value vault; careful Accept |
| 102 | Overwrite avoided in writers | 095/141 fixed | A |
| 103 | Reduce Transparency/Motion in chrome | 037/024/074 fixed | A |
| 104 | Menu-bar extra = menu not popover | 016/132 fixed; 121 peer | A — code: `.menuBarExtraStyle(.menu)` |
| 105 | Sparkle states fail-closed | 015 fixed | A |
| 106 | Persistence-degraded banner top | 004 fixed | A |
| 107 | Light/dark semantic palette | 024 fixed | A |
| 108 | Labeled button 3-level hierarchy | 026/066 fixed | A |
| 109 | HubToolPage 680 width cap | 118 peer | A |
| 110 | Relative time = system formatter | 073 fixed | A — `HubRelativeTime` → `RelativeDateTimeFormatter` |
| 111 | A11Y-28 surfaces (player/restore/board/extra/grips) | 005/042 fixed; 101/104 peers | A |
| 112 | First-run copy + Open panel | 083/136/052 fixed | A |
| 113 | Live search / counts / no-match | 033/045/047 fixed | A |
| 114 | Board drag preview / targeting / RM / edge scroll | 003/005/037/141 fixed | A |
| 115 | Workflow color + name + icon | 036/079 fixed | A |
| 116 | Persistent preview player + capture pause | 137 fixed; 100 peer | A |
| 117 | Preview candidate / paging / Compare | 134 fixed | A |
| 118 | Narrow window list↔detail swap @780 | 051 fixed | A |
| 119 | Analytics empty/zero + labeled stats | 050/087 fixed | A |
| 120 | Cache + background scan | 009/044 fixed; 110 peer | A |
| 121 | Quit alert safe default + recovery copy | 016 fixed | A — Keep Open is first button; Quit secondary |
| 122 | Vault fail-closed paths (copy/Test Restore/…) | 002/003/057 fixed | **B** — Friends+backup removal still gated |
| 123 | BPM pad / Space / clipboard / history confirm | 007/029/035/063/096 fixed | A — Space already daytime-Accept |
| 124 | Recorder meter / timer / banner / RM | 059/064/081 fixed; 126 peer | A |
| 125 | Shelf drag+Reveal; converter drop; Downloader validation | 030/061/063 fixed | A |
| 126 | Privacy purpose + in-tool Screen Recording copy | 059 fixed | A |

## Recommended verify batches (no code unless fail)

1. **Shell / menu** — 098, 104, 105, 121 (quick App menu + MenuBarExtra + quit alert)
2. **Settings / chrome / a11y** — 099, 100, 103, 106, 107, 108, 109, 111
3. **Archive / search / board** — 110, 113, 114, 115, 116, 118, 120
4. **Vault / restore** — 101, 102, 122 (122 with gated note)
5. **Tools** — 112, 117, 119, 123, 124, 125, 126

Promote rule: source + existing unit/GUI Accept of related IDs hold → `verified-no-change`. Regression found → reopen, fix, Accept, then `fixed`.

## Code spot-checks already done (2026-09-17 morning)

- **098** `AppMenu.swift`: About replaces `.appInfo`; Updates after `.appSettings`
- **104** `NikoMusicHubApp.swift`: `.menuBarExtraStyle(.menu)`
- **110** `HubRelativeTime.swift`: wraps `RelativeDateTimeFormatter` named style
- **121** quit `NSAlert`: first button Keep Music Hub Open; Quit is second; recovery copy present
