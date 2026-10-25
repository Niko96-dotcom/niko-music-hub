# NMH-004 GUI Accept (2026-09-17 ~00:23 CEST)

Shared proof: `dist/gui-accept/NMH-sev4-20260917-001129/` (isolated settings suite, stale bookmark seed, `DRY_RUN_OPEN=1`, **no** `FIXTURE_ROOT` so recovery path is used).

## Stale/denied bookmark → recovery card

| Check | Result |
|-------|--------|
| Seeded scan-only root with invalid bookmark `Data([0,1,2])` + onboarding completed | done (`suite-004.txt`) |
| UI shows **Archive access needs attention** (not first-run / not empty board) | **PASS** — `ax-004.txt` |
| **Choose Folder** + **Grant Access** controls present | **PASS** |
| **No songs yet** absent | **PASS** (0 hits) |
| Log: bookmark resolution failed | `app-004.stdout` |

## Verdict

**fixed**
