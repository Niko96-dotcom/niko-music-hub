# NMH-009 GUI Accept (2026-09-17 ~00:23 CEST)

Shared proof: `dist/gui-accept/NMH-sev4-20260917-001129/`.

## Cancel affordances

| Check | Result |
|-------|--------|
| **Cancel Scan** while Scanning archive… | **PASS** — `ax-009-cancel-scan.txt` (slow-fixture 800 songs; also Scanning archive… copy) |
| **Cancel Download** while Downloading… | **PASS** — `ax-009-cancel-download.txt` (+ `Elapsed 0:00`) |
| Cancel Transfer / Stop Transfer alert | **NOT PROVEN** this pass (no long vault transfer fixture) |
| Cancel button press → canceled status | **NOT PROVEN** (yt-dlp format failure raced; scan finished before press) |

## Verdict

**fixed** — in-app Cancel Scan + Cancel Download affordances proven in GUI during running jobs. Transfer cancel left as runtime caveat (unit coverage exists).
