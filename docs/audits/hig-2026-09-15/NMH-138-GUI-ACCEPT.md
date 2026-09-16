# NMH-138 GUI Accept (2026-09-16 CEST)

Fixture: `Fixtures/CubaseArchive`, isolated `NIKO_MUSIC_HUB_SETTINGS_SUITE`, `DRY_RUN_OPEN=1`.
Proof: `dist/gui-accept/NMH-138-20260916-212621/`.

## Code (already from NMH-039 + this pass)

- `NewSongSheet`: `Cancel` + `.cancelAction`, `Create Draft` + `.defaultAction`, name `.onSubmit`.
- `ProjectVaultRestoreSheet`: Cancel/default shortcuts already present.
- This pass: `Song > New Song Draft` (⇧⌘N) via `archiveNewSongDraftRequested`; Archive actions menu uses `Label` so AX can see it.

## Runtime checklist

| Check | Result |
|-------|--------|
| Open New Song Draft (⇧⌘N / Song menu) | **PASS** — Cancel + Create Draft visible |
| Esc dismisses without creating a folder | **PASS** — sheet gone; no new draft dir while Esc-only |
| Cancel dismisses | **PASS** |
| Return / Create Draft creates valid draft | **PASS** (folder created; see note) |
| Restore sheet Esc | **NOT RUN** — needs vault archive generation UI; code already has `.cancelAction` |
| VoiceOver order | **NOT RUN** (Inspector); controls labeled Cancel / Create Draft present in AX |

### Isolation note

Isolated suite did not override `outputFolder`, so Create wrote under the default
`~/Music/Niko Music Hub/Inbox/New Song Drafts/`. Test folders `NMH138EscTest` (and siblings)
were **deleted immediately** after observation. Future GUI Accept must set suite
`outputFolder` to a path under `dist/gui-accept/…/isolated-output` before Create.

## Verdict

New Song Esc/Cancel/Create path Accept **pass** with the isolation cleanup note.
Restore-sheet Esc still pending a vault fixture session — keep related follow-up on NMH-139/vault runs.
Ledger: treat New Song half as done; overall status `implemented-awaiting-runtime` until restore Esc is observed, **or** `verified-no-change` if restore is accepted on code parity with already-shipped `.cancelAction`.

Chosen: **implemented-awaiting-runtime** (restore Esc not observed).

## Follow-up (2026-09-16 23:10 CEST)

Restore-sheet Esc still **not run**. Synthetic vault fixtures exist for unit/runtime tests (`ProjectVaultSyntheticFixtures` / `LiveProjectVaultRuntimeTests.Fixture`), but wiring an archived generation + free Active pair into a suite-isolated GUI launch (security-scoped vault folder bookmarks + archive index + board card) was not completed in this unattended pass. No invented PASS. Stay `implemented-awaiting-runtime`.
