# NMH-139 GUI Accept (2026-09-16 CEST)

## Runtime first (spec)

Full Accept needs: fixture Active destination free, start **Get Local & Open**, stay on the board, watch progress without Manage storage.

## What exists in tree (no extra banner invented)

- `HubJobsStatusView` in tool sidebar (NMH-011) — shell jobs row.
- Archive footer `statusMessage` in `ArchiveBrowserView`.
- Card `vaultActivityMessage` / queue strings in `ArchiveBrowserViewModel+ProjectVaultQueue`.

## This session

Did **not** run Get Local on a vault fixture (no archived generation + free Active pair wired in the GUI Accept suite). CubaseArchive fixture is archive-browser songs, not a Project Vault restore pair.

## Verdict

Leave **implemented-awaiting-runtime**. Surfaces for noticeability are present; board-visible progress during Get Local still needs a dedicated vault fixture GUI pass. Do not add Archive-only banner (spec step 3).

## Follow-up (2026-09-16 23:10 CEST)

Get Local board noticeability still **not run** — same vault fixture GUI wiring gap as NMH-138 (needs Active-free archived pair under isolated suite; CubaseArchive fixture is not a Project Vault restore pair). Surfaces (jobs row / footer / card activity) remain in tree; no invented banner or PASS. Stay `implemented-awaiting-runtime`.

## Follow-up (2026-09-16 23:34 CEST) — Get Local board surface observed

Proof: `dist/gui-accept/NMH-138-139-vault-20260916-232458/` (same vault fixture pair as NMH-138).

### Run

1. After archived generation + free Active, opened **Get Local & Open** and confirmed restore.
2. Returned to **Board** during/after the transfer.
3. Tiny local fixture finished before mid-transfer ProgressView samples; by first AX sample (~1s) restore had completed.

### Surface actually visible on the board

| Surface | Observed? |
|---------|-----------|
| Archive footer `statusMessage` | **YES** — `Restored and verified in Active Projects. Sent to its DAW to open; check any project or plug-in prompts there.` (persisted across board samples in `nmh139-progress-final.txt`) |
| Card `vaultActivityMessage` / in-progress ProgressView | **NOT observed** (transfer too fast on this fixture) |
| HubJobsStatusView / shell jobs row | **NOT observed** for this vault restore |
| Extra Archive-only banner | **Not added** (per product decision) |

Active folder restored: `Active/NMH138 Synthetic Song/`.

Verdict: board-visible noticeability for this run is the **footer statusMessage**. No extra chrome. Promote NMH-139 to **fixed** with the mid-transfer caveat (needs a larger/slower fixture to observe live ProgressView).
