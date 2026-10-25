# NMH-034 GUI Accept (2026-09-16 ~23:50 CEST)

Shared proof: `dist/gui-accept/NMH-shell-sev2-20260916-233918/` (fixture CubaseArchive, isolated `NIKO_MUSIC_HUB_SETTINGS_SUITE`, `DRY_RUN_OPEN=1`, no live ~/Music writes).

## Song menu + archive letter shortcuts / focus

| Check | Result |
|-------|--------|
| Song menu: Open Project, Reveal in Finder, Show Versions, Open Preview | **PASS** |
| Space opens persistent preview player for selected song | **PASS — after AX select Neon Hook** |
| ⌘F remains Find | **PASS** |
| Unmodified o / p / f / d | **ATTEMPTED — no extra sheet under DRY_RUN_OPEN; Space proved archive key path** |
| Tab focus ring | **NOT RUN (visual); focusEffectDisabled removal is code-side** |

## Verdict

**fixed**

VoiceOver Inspector not used. Letter keys beyond Space left soft under dry-run.
