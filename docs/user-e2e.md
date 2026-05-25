# User E2E — Niko Music Hub

## Fixture smoke (automated)

```bash
./script/e2e_user_smoke.sh
```

This script:

1. Regenerates `Fixtures/CubaseArchive/` and `Fixtures/CubaseArchiveSummaryTruncation/`
2. Builds `dist/NikoMusicHub.app`
3. Runs the app with `NIKO_MUSIC_HUB_E2E_SMOKE=1` (CLI hook — not pgrep-only)
4. Drives the same `ArchiveUserFlowSmoke` path as unit tests: fixture root → scan → fuzzy search **neon hk** → dry-run open latest CPR
5. Asserts stdout includes user-flow markers, search match explainability (`search_match_summary`), CPR path, dry-run log, read-only write-probe, and unchanged fixture tree

Environment variables:

| Variable | Purpose |
|----------|---------|
| `NIKO_MUSIC_HUB_E2E_SMOKE=1` | Run smoke and exit (no UI required) |
| `NIKO_MUSIC_HUB_FIXTURE_ROOT` | Cubase archive fixture root |
| `NIKO_MUSIC_HUB_DRY_RUN_OPEN=1` | Log CPR path without launching Cubase |

## Real archive read-only smoke (manual)

Replace `<YOUR_ARCHIVE_ROOT>` with your Cubase projects folder:

```bash
swift run NikoMusicCoreSelfTest --real-root "<YOUR_ARCHIVE_ROOT>" --read-only
```

Expect song/CPR/preview counts only. The process must not write under the scanned root (`ReadOnlyArchivePolicy` write-probe).

## Diagnostics support summary

Pasteable scan diagnostics (`summary_line=` in exports and the in-app **Support summary**) list at most **five** song titles when multiple songs have warnings. Additional titles appear as `and N more` in the line. Full per-song warning rows remain in the exported diagnostics file under `song=` entries.

When truncation applies, exports also include:

- `summary_line_song_warning_titles_truncated=true`
- `summary_line_song_warning_titles_cap=5`
- `summary_line_song_warning_titles_omitted=<count>`

`./script/e2e_user_smoke.sh` also scans the eight-song **Summary Warning** truncation lab and asserts the exported `summary_line=` includes `and 3 more` plus the truncation metadata lines above. The in-app diagnostics panel shows a matching footnote under **Support summary** (`Support summary shows 5 warning song titles; 3 more listed below.`); smoke asserts that text via `diagnostics_panel_summary_truncation_footnote=`.

On the **Preview Ranking Lab** fixture, smoke asserts panel/export parity for the scan-level too-short callout (`preview_ranking_scan_callout=`) and the selected-song header (`preview_ranking_selected_header=`):

- `diagnostics_panel_ranking_scan_callout_match=`
- `diagnostics_panel_ranking_selected_header_match=`

When a selected song’s main preview was chosen by an equal-score tiebreak, the diagnostics panel shows a dedicated accent **preview tiebreak** line (export parity with `preview_rank_tiebreak=`). Smoke asserts panel/export parity on tiebreak fixtures:

- **Duration:** `diagnostics_panel_duration_tiebreak_header_match=` and `diagnostics_panel_duration_tiebreak_callout_match=`
- **Version:** `diagnostics_panel_version_tiebreak_callout_match=`
- **Extension:** `diagnostics_panel_extension_tiebreak_callout_match=`

## Local gates

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
```
