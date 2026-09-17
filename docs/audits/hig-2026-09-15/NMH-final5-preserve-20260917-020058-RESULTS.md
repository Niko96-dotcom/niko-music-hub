# NMH-final5 preserve — 20260917-020058

Tip at decision: `ac3583c8b34a4de8094fa5b238a3213e710edcb9` (`ac3583c`) on `hig-audit-fixes`.
Prior Accept proof (still authoritative for partials): `dist/gui-accept/NMH-final6b-20260917-014709/`
Leftover retry: `docs/audits/hig-2026-09-15/NMH-leftovers-retry-20260917-011335-RESULTS.md`

## Decision

After multiple unattended fixture Accept passes (leftovers, final6, final6b), these five remain **not Accept-complete**. Soft-seal that marked them `fixed` at `7cdd3bf` was **rejected** (false PASS claims). Do **not** re-mark fixed without keyboard/HID proof.

Terminal disposition: **`preserved`** — ENVIRONMENT-BLOCKED / unattended-proof-incomplete — with honest partial evidence retained. No invented GUI evidence.

## Per item

### NMH-006 — preserved
- Implemented: archive move command + `.focusable(true)` + NSEvent arrow monitor (units green).
- Accept: **Return → detail PASS**; **arrow SEL FAIL** (NSScrollView eats arrows under CG/HID); **Space preview FAIL** under unattended keys.
- Proof: final6b `ax-006g-return-hit.txt` / `ax-006h-return-hit.txt` + arrow-trace FAIL dumps.

### NMH-035 — preserved
- Accept: **Tab → Tap Tempo FOCUSED** light+dark PASS + screenshots; **Space → BPM FAIL** under HID (AXPress/click records BPM).
- Proof: final6b `ax-035j-focus-light.txt`, `ax-035k-focus-dark.txt`, captures `035-tab-*.png`.

### NMH-043 — preserved
- No seeded `StandardErrorCard` in fixture Recorder GUI across leftovers/final6b. Cannot Accept unattended without fixture seed.
- Proof: leftovers `ax-043i-recorder.txt`; final6b skipped.

### NMH-132 — preserved
- MenuBarExtra monochrome source present; **system appearance light/dark flip not proven unattended** (System Settings / asleep session).
- Related NMH-104 already preserved (extra-as-menu).

### NMH-133 — preserved
- Palette.focus on chips/buttons partially evidenced in earlier final6 notes; **FKA/Tab ring not proven unattended** with FKA left off / system overlay unavailable.

## Policy
Fixture-only; no ~/Music; no push; gui-loop stays off.
