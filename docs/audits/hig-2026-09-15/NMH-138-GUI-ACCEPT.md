# NMH-138 GUI Accept (2026-09-16 CEST)

Fixture: suite-isolated Project Vault (`NikoMusicHubGUIAcceptVault138139.…`), proof
`dist/gui-accept/NMH-138-139-vault-20260916-232458/`, `DRY_RUN_OPEN=1`.
Earlier New Song path: `dist/gui-accept/NMH-138-20260916-212621/`.

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
| Restore sheet Esc | **PASS** — sheet open (`ax-sheet4.txt` / `sheet4.png`); Esc clears Version/Cancel; Active stays empty (`nmh138-final2.txt`) |
| Restore sheet Cancel | **PASS** — `nmh138-cancel-final.txt` |
| VoiceOver order | **NOT RUN** (Inspector); controls labeled Cancel / Create Draft / Get Local present in AX |

### Isolation note (New Song)

Isolated suite did not override `outputFolder` on the first New Song pass, so Create wrote under the default
`~/Music/Niko Music Hub/Inbox/New Song Drafts/`. Test folders `NMH138EscTest` (and siblings)
were **deleted immediately** after observation. Vault restore Accept used proof `Active/` only.

### Vault fixture note

`seed-vault-gui` bookmarks Active/Archive into the suite; song archived via GUI Archive Now into
`Archive/generations/…`. Card control AX: `Restore local copy and open project` opens `ProjectVaultRestoreSheet`.

## Verdict

New Song Esc/Cancel/Create **and** Restore Esc/Cancel Accept **pass**.
Ledger: **fixed**.
