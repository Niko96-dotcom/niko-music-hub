# Phase 12: Metadata Core — Context

**Gathered:** 2026-05-30
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous defaults)

<domain>
## Phase Boundary

App-owned metadata on top of the phase 11 SQLite index: virtual titles, aliases, editable notes, manual main preview, and first-run archive root onboarding (CP-03–CP-06).

</domain>

<decisions>
## Implementation Decisions

- **Metadata table:** `song_metadata` in the same `archive-index.sqlite` as snapshot rows; keyed by song folder path (`Song.id`).
- **Merge point:** `ArchiveMetadataMerger` after every scan/cache load; ranker output is baseline, user fields overlay.
- **Display title:** `Song.effectiveDisplayTitle` = trimmed `virtualTitle` ?? scanner `displayTitle`; disk folder never renamed.
- **Preview:** `preview_selection_mode` `auto` | `manual`; manual ID kept across rescans when candidate still exists; revert restores ranker pick.
- **Search:** `MusicSearchMatcher` matches `effectiveDisplayTitle`, `aliases`, `appNote`, plus existing sidecar `notes.txt`.
- **Onboarding:** `AppSettings.archiveOnboardingCompleted`; full-screen picker when false + empty roots (no dev bootstrap); completing on first root add.
- **Read-only:** Metadata writes only under Application Support.

### Claude's Discretion

Alias editing UI (comma-separated field vs. single-line add); exact onboarding copy.

</decisions>

<code_context>
## Existing Code Insights

- Phase 11: `SQLiteArchiveIndexStore` single-row JSON snapshot; `ArchiveBrowserViewModel` loads cache then scans.
- `Song` has `displayTitle`, `mainPreviewCandidateID`, `sidecarNotes`; `PreviewConfidenceRanker` picks auto preview.
- `RootSelectionView` handles roots inline; `ArchiveDefaultRootPolicy` bootstraps dev paths only.

</code_context>

<specifics>
## Success Criteria (from ROADMAP)

1. Virtual rename changes UI title only.
2. App notes + aliases persist and appear in search.
3. Manual preview pick + revert to auto.
4. First-run guided root flow when settings empty.
5. `./script/ci.sh` green.

</specifics>
