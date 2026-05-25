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

After the fixture scan, the diagnostics panel lists **Skipped at roots** entries (`LOOSE_FILE.txt`, `README.md` on the generated fixture). Smoke asserts each panel line matches an export `skipped=kind label=… reason=…` row via `diagnostics_panel_skipped_entries_lines_match=` and `skipped_entries=2`.

When a song search is active (fixture flow uses **neon hk**), the diagnostics panel shows **Active search** with the query, match count, and per-match explainability lines. Smoke asserts panel/export parity with the export `active_search` block:

- `diagnostics_panel_search_query_line_match=` (panel query line matches export `search_query=` / `search_matches=`)
- `diagnostics_panel_search_match_lines_match=` (each panel match line matches an export `search_match title=… summary=…`)

Fixture fuzzy/active searches all use the same **Active search** panel section (export `active_search` block). Smoke asserts panel/export parity per flow:

| Query | Marker prefix |
|-------|----------------|
| **neon hk** | `diagnostics_panel_search_*` |
| **project** (scan warning) | `diagnostics_panel_warning_search_*` |
| **ncpr fnd** (fuzzy scan warning) | `diagnostics_panel_fuzzy_warning_search_*` |
| **nts nly** (sidecar notes) | `diagnostics_panel_notes_search_*` |
| **brkn fld** (folder) | `diagnostics_panel_folder_search_*` |
| **neohkv2** (CPR file) | `diagnostics_panel_cpr_search_*` |
| **ranking lab v3 mx** (preview file) | `diagnostics_panel_preview_search_*` |

Each pair: `*_query_line_match=` and `*_match_lines_match=` (panel lines match export `search_query=` / `search_matches=` / `search_match title=… summary=…`).

When a song is selected (fixture flow selects **Broken Folder Example** after scan), the diagnostics panel shows **Selected song** with title, CPR summary, scan warnings, and sidecar notes. Smoke asserts panel/export parity with the export `selected_song` block:

- `diagnostics_panel_selected_song_title_line_match=` (panel title matches export `selected_song_title=`)
- `diagnostics_panel_selected_song_cpr_line_match=` (panel CPR line matches export `selected_song_cpr=`)
- `diagnostics_panel_selected_song_warning_lines_match=` (panel warnings match export `selected_song_warning=`)
- `diagnostics_panel_selected_song_notes_line_match=` (panel notes line matches export `selected_song_notes=`)

When a skipped-entry search is active (fixture flow uses fuzzy query **lse fle** → **LOOSE_FILE.txt**), the diagnostics panel shows **Active skipped search** with the query, match count, and per-match explainability lines (`fuzzy skipped label` in summaries). Smoke asserts panel/export parity with the export `active_skipped_search` block:

- `diagnostics_panel_skipped_search_query_line_match=` (panel query line matches export `skipped_search_query=` / `skipped_search_matches=`)
- `diagnostics_panel_skipped_search_match_lines_match=` (each panel match line matches an export `skipped_search_match label=… kind=… summary=…`)

On the **Preview Ranking Lab** fixture, smoke asserts panel/export parity for the scan-level too-short callout (`preview_ranking_scan_callout=`), the selected-song header (`preview_ranking_selected_header=`), per-song too-short breakdown lines (`too_short_song=`), the tiebreak legend (`preview_ranking_tiebreak_legend=`), the selected-song main preview summary (`main_preview_summary=`), and ranked preview lines (`preview_rank_line=`):

- `diagnostics_panel_ranking_scan_callout_match=`
- `diagnostics_panel_ranking_selected_header_match=`
- `diagnostics_panel_ranking_too_short_breakdown_match=` (panel line names the same clips as export `too_short_song=`)
- `diagnostics_panel_ranking_tiebreak_legend_match=` (panel legend text matches export `preview_ranking_tiebreak_legend=`)
- `diagnostics_panel_ranking_main_preview_summary_match=` (panel summary matches export `main_preview_summary=`)
- `diagnostics_panel_ranking_preview_rank_lines_match=` (each panel ranked line matches an export `preview_rank_line=`)

When a selected song’s main preview was chosen by an equal-score tiebreak, the diagnostics panel shows a dedicated accent **preview tiebreak** line (export parity with `preview_rank_tiebreak=`). Smoke asserts panel/export parity on tiebreak fixtures:

- **Duration:** `diagnostics_panel_duration_tiebreak_header_match=` and `diagnostics_panel_duration_tiebreak_callout_match=`
- **Version:** `diagnostics_panel_version_tiebreak_callout_match=`
- **Extension:** `diagnostics_panel_extension_tiebreak_callout_match=`

## Local gates

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
```
