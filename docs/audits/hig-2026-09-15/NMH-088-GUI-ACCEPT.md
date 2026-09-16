# NMH-088 GUI Accept

**Status:** PASS (2026-09-17 ~01:26 CEST)

**Proof:** `dist/gui-accept/NMH-leftovers-retry-20260917-011335/`

- Amber Moth playing (3:20); `PLAY=Pause preview`
- Option-Right/Left seek ≈ ±5s while playing (`ax-088i-measure.json`)
- Song menu Skip Forward/Back ≈ ±5s while playing
- Skip buttons ≈ +5s
- `menu_en=true` after focus/`canSkipPreview` firstResponder gate

Supporting fix: `ArchiveShortcutFocusPolicy.claimArchiveKeyFocus` + `canSkipPreview` uses `allowsSongShortcuts(archiveFocused: true)` (text-field gate only, not SwiftUI archive FocusState).
