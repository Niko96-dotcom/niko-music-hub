# NMH-025 GUI Accept (2026-09-17 ~00:36 CEST)

Shared proof: `dist/gui-accept/NMH-sev5-20260917-002609/` (fixture CubaseArchive, suite `NikoMusicHubGUIAcceptSev5.E432AAA6-4572-4187-9514-BE7D7CE6ED7D`, `DRY_RUN_OPEN=1`).

## Quiet fields + focus ring

| Check | Result |
|-------|--------|
| Song info → Edit song info shows Display title / Aliases / Song note | **PASS** (`ax-025-fields-dump.txt` placeholders Virtual title / rave hook / Your note) |
| Focus Display title | **PASS** — AX focused=true (`ax-025-focus.txt`) |
| macOS focus ring visible (quiet/.plain field) | **PASS** — blue ring in `captures/025-focus-title.png` |

## Verdict

**fixed**
