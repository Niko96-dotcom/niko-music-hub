# NMH-074 GUI Accept (2026-09-17 ~00:36 CEST)

Shared proof: `dist/gui-accept/NMH-sev5-20260917-002609/`.

## Appearance-aware highlight/sheen

| Check | Result |
|-------|--------|
| Light vs Dark hub surfaces | **PASS** — `captures/appearance-light.png` vs `appearance-dark.png` (Settings Appearance chips) |
| Highlight tokens unit | **PASS** — `testHighlightTokensExposed` |
| Reduce Transparency skips sheen | **NOT RUN** (code-gated; toggle not exercised) |

## Verdict

**fixed** (Reduce Transparency caveat)
