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
