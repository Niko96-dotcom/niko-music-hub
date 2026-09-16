# NMH-139 GUI Accept (2026-09-16 CEST)

## Runtime (observed)

Fixture: same suite-isolated vault pair as NMH-138 —
`dist/gui-accept/NMH-138-139-vault-20260916-232458/` (`DRY_RUN_OPEN=1`).

| Check | Result |
|-------|--------|
| Active free + archived generation | PASS — generation under proof `Archive/generations/…` |
| Start **Get Local & Open** from board | PASS — card `Restore local copy and open project` → sheet → confirm |
| Stay on board (no Manage storage) | PASS |
| Board-visible progress / status | **PASS** — Archive footer `statusMessage`: “Restored and verified in Active Projects. Sent to its DAW to open; check any project or plug-in prompts there.” (`nmh139-final.txt` samples 1–10, `board-during-getlocal.png`) |
| Jobs row / card `vaultActivityMessage` mid-copy | NOT OBSERVED — 21-byte synthetic CPR finished before AX samples; no invented banner |

Restore wrote Active under the proof dir only; DAW open dry-ran (`openingInCubase` in suite DB).

## Surfaces in tree (unchanged)

- `HubJobsStatusView` in tool sidebar (NMH-011).
- Archive footer `statusMessage` in `ArchiveBrowserView` — **observed** for this Accept.
- Card `vaultActivityMessage` / queue strings — present; not caught mid-flight on this tiny fixture.

## Verdict

Board noticeability of Get Local **pass** via footer status (honest; no new banner).
Ledger: **fixed**.
