# NMH-030 GUI Accept (2026-09-17 CEST)

Proof: `dist/gui-accept/NMH-sev45-20260917-001333/`

| Check | Result |
|-------|--------|
| Seeded Ready `available` wav into isolated `output-inbox.json` | done |
| Persistent **Reveal** + **Open** on Ready row (not hover-only) | **PASS** — `ax-full2.txt` |
| Row status Ready + filename | **PASS** |
| VO actions Reveal in Finder / Open / Analyze BPM | **PASS** — `ax-030-row.txt` |
| Drag grip always visible when dragReady | **PASS** (code: not hover-gated; `accessibilityHidden(true)` decorative) |

## Verdict
**fixed**
