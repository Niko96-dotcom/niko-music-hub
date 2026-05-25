# Autonomous backlog — 2026-05-25

## Picked (music-50)

Diagnostics: export explicit truncation metadata when `summary_line` omits song warning titles beyond the cap.

## Completed (music-50)

- `summaryLineSongWarningTitlesTruncated` / `summaryLineSongWarningTitlesOmittedCount` on `ArchiveScanDiagnostics`
- Export lines: `summary_line_song_warning_titles_truncated`, `_cap`, `_omitted`
- Tests: truncation flags + exporter metadata (TDD red → green)
- Documented five-title cap in `docs/user-e2e.md`
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-49)

Diagnostics: cap/truncate song warning titles in pasteable `summary_line=` when many songs have warnings.

## Next best TODO

- Search: collaborator/alias fields per SPEC §10 (needs metadata layer beyond sidecar notes)
- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Preview ranking: chorus/loudness preview start, manual overrides (deferred v0.2+)
- Fixture/E2E proof of summary-line truncation when many songs have warnings (optional; unit-tested today)
