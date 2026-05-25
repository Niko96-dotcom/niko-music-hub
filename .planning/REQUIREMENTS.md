# Requirements: Outside Cubase Hub

**Defined:** 2026-05-23
**Milestone:** v1.1 Production-Ready Tools
**Core Value:** Repeated production chores outside Cubase should become fast, local, reliable, and drag-and-drop ready for a Cubase project.

## v1.1 Requirements

Requirements close v1.0 verification gaps and production-trust issues. Carry-over IDs (DL, REC, UX) re-open until verified in v1.1 phases.

### Downloader Reliability & Verification

- [x] **DL-01**: User can paste or enter a supported website URL for download. *(verified Phase 7 — human UAT optional)*
- [x] **DL-02**: App detects yt-dlp availability/version and guides the user if it is missing or outdated. *(verified Phase 7)*
- [x] **DL-03**: User can start a download job with output location and basic media/output options. *(verified Phase 7)*
- [x] **DL-04**: Download jobs show progress, logs, completion, and errors. *(verified Phase 7)*
- [x] **DL-05**: Downloaded files are added to the shared output inbox with source URL metadata. *(verified Phase 7)*
- [x] **DL-06**: Downloader passes URLs and arguments safely without shell string interpolation. *(verified Phase 7)*
- [x] **DL-07**: Downloader UI clearly scopes use to material the user is allowed to access and save. *(verified Phase 7)*
- [x] **DL-08**: Simulate/metadata step rejects non-zero yt-dlp exit and does not enqueue a download job.
- [x] **DL-09**: Download failure surfaces actionable yt-dlp stderr in the UI (not a silent or generic-only message).
- [x] **DL-10**: In-progress downloader UI, use case, view model, and shared AppCore error components are committed and integrated.

### Internal Audio Recorder

- [x] **REC-01**: App checks macOS compatibility and explains required system audio recording permission before capture. *(Phase 8 — human hardware proof pending)*
- [x] **REC-02**: User can start and stop internal Mac/system audio recording using real Core Audio process taps. *(Phase 8)*
- [x] **REC-03**: Recording writes a playable WAV PCM file with real captured audio to the shared output inbox (preset honored). *(Phase 8 — human audible-content check pending)*
- [x] **REC-04**: UI shows active recording state, elapsed time, and an obvious stop control during real capture. *(Phase 8)*
- [x] **REC-05**: Recording failure states identify permission denied, API failure, or output-file problems clearly on target hardware. *(Phase 8)*
- [x] **REC-06**: User can reveal or drag the recorded WAV for Cubase import after real capture. *(Phase 8)*

### Converter & Output Handoff

- [ ] **CONV-06**: User can complete an end-to-end conversion in the running app and find verified Cubase-ready WAV in the configured output folder. *(Phase 9 human UAT pending)*
- [ ] **CONV-07**: User can drag a converted WAV from the app or output inbox into Cubase or Finder-compatible targets. *(Phase 9 human UAT pending)*
- [x] **HUB-01**: Output inbox refreshes when new file-producing jobs complete without requiring the inspector view to be recreated. *(Phase 9)*

### Hub Polish & Shared UX

- [x] **UX-03**: App provides concise, recoverable error messages for helper tools, permissions, and unsupported files. *(Phase 10 spot-check)*
- [x] **UX-04**: App provides keyboard shortcuts for frequent actions such as tap, reset, and start/stop recording. *(Phase 10 spot-check)*
- [x] **UX-05**: User can see accurate helper health for yt-dlp and FFmpeg (found, version/path, actionable when missing). *(Phase 10)*
- [x] **UX-06**: File-producing tools use shared AppCore error presentation (`StandardErrorCard` / `AppError`) consistently. *(Phase 10)*

### Quality & Verification Discipline

- [x] **QA-01**: All SPM test targets pass via `scripts/test.sh` with zero failures (permission-dependent skips documented). *(Phase 10)*
- [x] **QA-02**: Each v1.1 phase (7–10) produces `VERIFICATION.md` before the phase is marked complete. *(Phase 10)*

## Future Requirements

Deferred beyond v1.1. Tracked but not in current roadmap.

### Analysis & Prep

- **ANAL-01**: BPM/key/loudness analysis beyond tapping
- **PREP-01**: Sample prep chains (trim, fade, naming)

### Distribution

- **DIST-01**: Bundled yt-dlp/FFmpeg with licensing, updates, and notarization path
- **DIST-02**: Mac App Store distribution

### New Tools

- **TOOL-01**: Additional hub utilities beyond the four existing tools

## Out of Scope (v1.1)

| Feature | Reason |
|---------|--------|
| Mac App Store / bundled helpers release | Packaging and licensing not settled; health-check UX only |
| BPM/key/loudness analysis | Not required to make existing tools production-ready |
| Sample prep chains | Out of converter/recorder stabilization scope |
| New hub tools | v1.1 stabilizes four existing tools only |
| DRM / paywall bypass | Downloads only for material the user may access |
| Cubase plugin integration | Companion app remains outside the DAW |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DL-01 | Phase 7 | Satisfied (human UAT optional) |
| DL-02 | Phase 7 | Satisfied |
| DL-03 | Phase 7 | Satisfied |
| DL-04 | Phase 7 | Satisfied |
| DL-05 | Phase 7 | Satisfied |
| DL-06 | Phase 7 | Satisfied |
| DL-07 | Phase 7 | Satisfied |
| DL-08 | Phase 7 | Satisfied |
| DL-09 | Phase 7 | Satisfied |
| DL-10 | Phase 7 | Satisfied |
| REC-01 | Phase 8 | Pending |
| REC-02 | Phase 8 | Pending |
| REC-03 | Phase 8 | Pending |
| REC-04 | Phase 8 | Pending |
| REC-05 | Phase 8 | Pending |
| REC-06 | Phase 8 | Pending |
| CONV-06 | Phase 9 | Pending |
| CONV-07 | Phase 9 | Pending |
| HUB-01 | Phase 9 | Pending |
| UX-03 | Phase 10 | Pending |
| UX-04 | Phase 10 | Pending |
| UX-05 | Phase 10 | Pending |
| UX-06 | Phase 10 | Pending |
| QA-01 | Phase 10 | Pending |
| QA-02 | Phase 10 | Pending |

**Coverage:**
- v1.1 requirements: 25 total
- Mapped to phases: 25
- Unmapped: 0 ✓

---
*Requirements defined: 2026-05-23*
*Last updated: 2026-05-23 after v1.1 milestone initialization*
