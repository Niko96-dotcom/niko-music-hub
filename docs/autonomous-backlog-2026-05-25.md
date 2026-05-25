# Autonomous backlog — 2026-05-25

## Picked (music-02)

Preview ranking v0.2: parsed version tiebreak, extension preference, WAV duration plausibility, deterministic `confidenceReasons`, fixture lab song, Song detail explainability.

## Completed

- `PreviewCandidate` now carries `fileExtension`, `detectedVersionNumber`, `durationSeconds`
- `PreviewFilenameParser`, `PreviewWAVDurationReader`, richer `PreviewConfidenceRanker` (version/extension/duration + stable tiebreaks)
- `Preview Ranking Lab` fixture song + expanded `PreviewConfidenceRankerTests`
- `SongDetailView` shows main preview filename and joined confidence reasons
- `./script/ci.sh` and `./script/e2e_user_smoke.sh` green (4 fixture songs)

## Next best TODO

- Richer archive diagnostics surface (warnings/counts/root state) for operators
- Optional SwiftUI Accessibility drive only if needed; keep view-model smoke as primary gate
- E2E still lacks full interactive app/user-flow coverage beyond fixture smoke hook
