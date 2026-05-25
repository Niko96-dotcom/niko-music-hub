# Autonomous backlog — 2026-05-25

## Picked (music-06)

Archive diagnostics UX: show scan summary and redacted archive roots in the sidebar diagnostics panel (operators no longer need export-only root visibility).

## Completed

- `ArchiveScanDiagnostics.displayRootPaths(homeDirectory:)` redacts `~` paths via `DiagnosticsPathRedactor`
- `ArchiveDiagnosticsPanelView` shows `summaryLine` and per-root bullets
- Tests: `ArchiveScanDiagnosticsTests`, extended `ArchiveBrowserViewModelTests`
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green

## Prior (music-05)

Search result ranking: sort matches by match quality (title > folder > filenames > fuzzy) instead of scan order.

## Prior (music-04)

Fuzzy song search: tokenized AND matching, diacritic/punctuation folding, subsequence typo tolerance; E2E smoke uses `neon hk` and asserts diagnostics counts.

## Prior (music-03)

Archive scan diagnostics: counts, warnings, root paths, latest scan time, skipped-at-root entries, redacted export to temp only.

## Next best TODO

- E2E still lacks full SwiftUI Accessibility click-through (view-model smoke remains primary gate)
- Search: collaborator/alias/note fields per SPEC §10 (no metadata layer yet)
- Search match explainability in UI (why a song ranked where it did)
- Deeper per-folder skip reasons inside song folders if operators need them
