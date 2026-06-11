# Requirements: Niko Music Hub

**Defined:** 2026-06-11
**Milestone:** v1.4 Downloader Reliability
**Core Value:** Repeated production chores outside Cubase should become fast, local, reliable, and drag-and-drop ready for a Cubase project.

**Source research:** `.planning/research/SUMMARY.md`
**Source audit:** 2026-06-11 downloader audit attached to `$gsd-new-milestone`

## v1.4 Requirements

### Command Truth

- [ ] **CMD-01**: User sees real downloader progress from the app's actual `yt-dlp` command.
- [ ] **CMD-02**: Long valid downloads are not killed solely because they exceed 90 seconds.
- [ ] **CMD-03**: Stalled downloads fail with a clear stall/timeout message after no meaningful output or progress.
- [ ] **CMD-04**: Downloader preflight validates the selected format path and prevents accidental playlist expansion.
- [ ] **CMD-05**: Downloader output collection survives split UTF-8 chunks and still finds final output files.

### Helper Health

- [ ] **HLTH-01**: User can see when `yt-dlp` is missing, unusable, available, or outdated.
- [ ] **HLTH-02**: Outdated `yt-dlp` guidance tells the user how to update through the app's existing helper flow.
- [ ] **HLTH-03**: Retry behavior matches real transient failures, including "timed out" wording and common network failures.
- [ ] **HLTH-04**: Downloader jobs use human-readable titles instead of generic URL path fragments like `watch`.

### Output Contract

- [ ] **OUT-01**: Completed downloader jobs pass output file URLs as structured data to inbox ingestion.
- [ ] **OUT-02**: Downloader inbox ingestion no longer depends on synthetic `[download] Destination:` log lines.
- [ ] **OUT-03**: Diagnostic logs remain useful for debugging without becoming the source of truth for output files.

### Media Handoff

- [ ] **HAND-01**: User can reveal safe completed downloader media files in Finder.
- [ ] **HAND-02**: User can open safe completed downloader media files from the output inbox.
- [ ] **HAND-03**: User can drag safe completed downloader media files from the output inbox to Finder/Cubase-compatible targets.
- [ ] **HAND-04**: Output inbox shows appropriate icons/status for common downloader media types such as MP3, M4A, MP4, and WEBM.
- [ ] **HAND-05**: WAV verification remains strict for converter/recorder outputs while downloader media uses an explicit safe media allowlist.

### Real UAT

- [ ] **UAT-01**: v1.4 includes deterministic tests for progress markers, stall handling, helper health, structured output handoff, and media handoff.
- [ ] **UAT-02**: v1.4 includes opt-in/live downloader verification that exercises real `yt-dlp` behavior beyond the previous 18-second happy path.
- [ ] **UAT-03**: v1.4 verification proves helper-path behavior from app-like stripped environments still works.
- [ ] **UAT-04**: Milestone close includes documented evidence for downloader success, failure, progress, and media handoff flows.

## Future Requirements

Deferred beyond v1.4.

- **PLAY-01**: Playlist/channel batch download workflows.
- **UPD-01**: Bundled helper updater inside the app.
- **AUTH-01**: Auth/cookie/browser-profile flows for sites that require login.
- **DIAG-01**: Per-site advanced remediation suggestions.

## Out of Scope (v1.4)

| Feature | Reason |
|---------|--------|
| Circumventing paywalls, DRM, or site restrictions | Existing product boundary remains unchanged. |
| Replacing yt-dlp with an embedded Python runtime | Violates native-product boundary and adds packaging risk. |
| Playlist/channel UX | Single-URL reliability must become boring first. |
| Bundled helper auto-update | Useful later, but Homebrew/helper guidance is enough for v1.4. |
| New archive-browser intelligence | v1.4 is scoped to downloader reliability and output handoff. |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CMD-01 | TBD | Pending |
| CMD-02 | TBD | Pending |
| CMD-03 | TBD | Pending |
| CMD-04 | TBD | Pending |
| CMD-05 | TBD | Pending |
| HLTH-01 | TBD | Pending |
| HLTH-02 | TBD | Pending |
| HLTH-03 | TBD | Pending |
| HLTH-04 | TBD | Pending |
| OUT-01 | TBD | Pending |
| OUT-02 | TBD | Pending |
| OUT-03 | TBD | Pending |
| HAND-01 | TBD | Pending |
| HAND-02 | TBD | Pending |
| HAND-03 | TBD | Pending |
| HAND-04 | TBD | Pending |
| HAND-05 | TBD | Pending |
| UAT-01 | TBD | Pending |
| UAT-02 | TBD | Pending |
| UAT-03 | TBD | Pending |
| UAT-04 | TBD | Pending |

**Coverage:**
- v1.4 requirements: 21 total
- Mapped to phases: 0
- Unmapped: 21

---
*Requirements defined: 2026-06-11 from `.planning/research/SUMMARY.md`*
*Last updated: 2026-06-11 after v1.4 requirement approval*
