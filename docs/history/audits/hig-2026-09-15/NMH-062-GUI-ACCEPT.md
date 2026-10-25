# NMH-062 GUI Accept (2026-09-17 ~00:23 CEST)

Shared proof: `dist/gui-accept/NMH-sev4-20260917-001129/`.

## Determinate progress / stall signal

| Check | Result |
|-------|--------|
| While Downloading…, show **Elapsed m:ss** (not silent) | **PASS** — `Elapsed 0:00` in `ax-009-cancel-download.txt` / `ax-062-during.txt` |
| Do **not** show `0% complete` at start | **PASS** — no `0% complete` hits in progress dumps |
| After 30s without data: Still working… hint | **NOT PROVEN** — download failed (format unavailable) before 30s |

## Verdict

**fixed** — elapsed caption + no bogus 0% at start proven. 30s stall hint caveat.
