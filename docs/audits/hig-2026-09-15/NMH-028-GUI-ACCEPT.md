# NMH-028 GUI Accept (2026-09-17 ~00:36 CEST)

Shared proof: `dist/gui-accept/NMH-sev5-20260917-002609/`.

## HubChoiceChips platform grouping / height

| Check | Result |
|-------|--------|
| Appearance chips Follow System / Light / Dark | **PASS** (`ax-028-settings.txt`) |
| Height 28 pt | **PASS** — AX frames h=28.0 (`ax-028-chips.txt`) |
| Group under Appearance + selected state | **PASS** — group desc=Appearance; sel=[1] on active |
| Wrap at narrow Settings width | **NOT OBSERVED** — Settings min width still one row; unit wrap test PASS |

## Verdict

**fixed** (wrap caveat)
