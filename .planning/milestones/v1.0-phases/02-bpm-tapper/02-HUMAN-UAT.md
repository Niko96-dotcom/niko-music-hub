---
status: passed
phase: 02-bpm-tapper
source: [02-VERIFICATION.md]
started: 2026-05-04T14:19:10Z
updated: 2026-05-04T16:42:28Z
---

# Phase 02 Human UAT

## Current Test

Core BPM interaction controls and estimator smoothing are human-confirmed in the running macOS app. A final whole-number BPM display polish is applied.

## Tests

### 1. Mouse tap surface
expected: Selecting BPM Tapper and clicking inside the tap pad records taps and updates BPM; clicking outside the pad does not record taps.
result: passed - User screenshot on 2026-05-04 shows BPM Tapper selected with 9 taps recorded and a stable live BPM estimate of 116.3 in the running app.

### 2. Focus-scoped Space tapping
expected: Space records taps while the BPM tap surface is focused, and does not record taps after focus moves away.
result: passed - User reported "everything works" after the focus/keyboard/control checklist, with only estimator math feel called out.

### 3. Escape reset preserves saved history
expected: After saving a BPM, pressing Escape resets the current tap run while the saved recent-tempo row remains.
result: passed - User reported "everything works" after the save/reset/history checklist, with only estimator math feel called out.

### 4. Adjustment, copy, save, row copy, and clear history
expected: Half-Time and Double-Time change the visible value; Copy BPM writes only the number; Save BPM creates a history row; Copy Saved BPM copies that row value; Clear History removes saved rows after confirmation.
result: passed - User reported "everything works" after the adjustment/copy/save/history checklist, with only estimator math feel called out.

### 5. Tempo estimate stability
expected: The BPM estimate becomes steadier with continued tapping and does not feel like it frequently resets after an uneven tap.
result: passed - User retested after the smoothing/recovery fix and reported it feels better.

### 6. Whole-number BPM display
expected: Displayed and copied BPM values use whole numbers only; no `.5` or single-decimal values are shown.
result: fix applied - BPM display, current copy, and saved-row copy now round to whole numbers. Automated copy regression added; visual retest still welcome.

## Summary

total: 6
passed: 5
issues_found: 2
issues_resolved: 2
pending: 0
partial: 0
skipped: 0
blocked: 0

## Gaps

- Optional visual retest that live BPM display and history rows show whole numbers only.
