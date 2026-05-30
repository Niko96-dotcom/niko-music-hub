---
phase: "12"
status: passed
verified: "2026-05-30"
---

# Phase 12 Verification

## Must-haves

| Criterion | Status |
|-----------|--------|
| Virtual rename changes display title only (disk unchanged) | ✅ `Song.virtualTitle` + `effectiveDisplayTitle` |
| Song notes persist and appear in search | ✅ `appNote` + `MusicSearchMatcher` |
| Aliases searchable | ✅ |
| Manual main preview + revert to auto | ✅ `PreviewSelectionMode` + merger |
| First-run roots UX when settings empty | ✅ `ArchiveFirstRunView` + `archiveOnboardingCompleted` |
| `./script/ci.sh` green | ✅ |

## Tests added

- `ArchiveMetadataMergerTests`
- `SQLiteSongUserMetadataStoreTests`
- `ArchiveBrowserViewModelTests` (onboarding, virtual title, manual preview)
