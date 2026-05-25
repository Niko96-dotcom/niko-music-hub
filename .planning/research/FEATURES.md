# Feature Research

**Domain:** Native macOS music-production utility hub
**Researched:** 2026-05-04
**Confidence:** MEDIUM-HIGH

## Feature Landscape

### Table Stakes (Users Expect These)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| BPM tapper | The user already uses a web tapper repeatedly. | LOW | Needs tap input, reset, average, half/double tempo, copy/save. |
| Internal audio recording to WAV | Core requested workflow: capture computer audio and drag WAV into Cubase. | HIGH | Permission-heavy and should be validated early. |
| M4A to WAV conversion | Common Cubase prep chore named by user. | MEDIUM | Use native conversion where possible, FFmpeg fallback for robustness. |
| Website download queue | User explicitly linked yt-dlp as desired class of workflow. | MEDIUM | Needs URL input, progress, output, and safe error reporting. |
| Output inbox | All tools produce files that should be easy to drag into Cubase. | MEDIUM | Shared file list, reveal in Finder, preview/playback, drag-out. |
| Tool health checks | External helper tools can be missing/outdated. | MEDIUM | Show yt-dlp/FFmpeg availability, version, and next action. |
| Modular app shell | User explicitly wants new ideas to be easy. | MEDIUM | Feature registry, isolated state, shared services. |

### Differentiators (Competitive Advantage)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Cubase project preset | WAV output matches the current project sample rate/bit depth. | LOW-MEDIUM | Prevents subtle import friction. |
| Clipboard URL intake | Paste/copy a URL and queue it quickly without opening Terminal. | LOW | Keep permission and privacy simple; no global clipboard watcher in v1 unless explicitly enabled. |
| Source notes and naming templates | Downloaded/recorded files stay traceable. | MEDIUM | Useful for sample provenance and session organization. |
| One-click sample prep chain | Convert, normalize, trim silence, and name in one operation. | HIGH | Defer until base converter is stable. |
| BPM/key/loudness analysis | Adds production value beyond utility wrapping. | HIGH | Good future module once WAV pipeline exists. |
| Global quick capture | Start capture while focused in another app. | MEDIUM-HIGH | Requires global shortcuts and careful permission UX. |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Full browser inside the app | Convenient for downloads. | Expands scope, privacy surface, and maintenance burden. | Paste URL or drag URL into downloader. |
| Everything in one dashboard view | Looks simple initially. | Becomes hard to add tools cleanly. | Sidebar/tool registry with shared job output. |
| Auto-download whatever is playing | Feels magical. | Raises consent, legality, and reliability issues. | Explicit URL input and user-owned material. |
| Full waveform editor | Nice for trimming. | Duplicates DAW/editor functionality. | Simple preview plus future trim/fade module. |

## Feature Dependencies

```text
Feature Registry
    -> App Shell
    -> Tool Surfaces

Output Inbox
    -> Conversion
    -> Recording
    -> Downloader

Tool Health Checks
    -> Downloader
    -> FFmpeg fallback conversion

Project Audio Preset
    -> Conversion
    -> Recording WAV export

System Audio Permission
    -> Internal Recording
```

### Dependency Notes

- **Feature Registry before tools:** Every tool should plug into the same shell instead of creating bespoke navigation/state.
- **Output Inbox before file-producing tools:** Conversion, recording, and downloads all need consistent output behavior.
- **Tool Health before downloader:** yt-dlp and FFmpeg failures should be understandable before the user queues a job.
- **Project Preset before WAV polish:** The app needs one source of truth for sample rate, bit depth, and output naming.

## MVP Definition

### Launch With (v1)

- [ ] App shell with feature registry and shared output inbox.
- [ ] BPM tapper that works offline and replaces the website.
- [ ] M4A/common audio to WAV conversion with project preset.
- [ ] Internal system audio recording to WAV.
- [ ] yt-dlp-backed URL download workflow with progress/errors.
- [ ] Tool health/settings screen for FFmpeg and yt-dlp.

### Add After Validation (v1.x)

- [ ] Playback preview for output files.
- [ ] Naming templates with BPM/source/date tokens.
- [ ] Clipboard URL intake.
- [ ] Simple trim silence and fade in/out.
- [ ] Global keyboard shortcut for quick capture.

### Future Consideration (v2+)

- [ ] BPM/key detection from audio files.
- [ ] Loudness/RMS/peak analysis.
- [ ] Batch sample-prep chains.
- [ ] Cubase project folder watcher.
- [ ] Stem separation or AI-assisted cleanup.

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Feature registry/app shell | HIGH | MEDIUM | P1 |
| BPM tapper | HIGH | LOW | P1 |
| M4A to WAV conversion | HIGH | MEDIUM | P1 |
| Internal audio recording | HIGH | HIGH | P1 |
| yt-dlp downloader | HIGH | MEDIUM | P1 |
| Output inbox | HIGH | MEDIUM | P1 |
| Tool health checks | MEDIUM | MEDIUM | P1 |
| Naming templates | MEDIUM | MEDIUM | P2 |
| Clipboard URL intake | MEDIUM | LOW | P2 |
| Key/loudness analysis | MEDIUM | HIGH | P3 |

**Priority key:**
- P1: Must have for launch
- P2: Should have, add when possible
- P3: Nice to have, future consideration

## Competitor Feature Analysis

| Feature | Existing Habit/Tool | Limitation | Our Approach |
|---------|---------------------|------------|--------------|
| BPM tapper | beatsperminuteonline.com | Requires leaving app/browser, no integration with output/project context. | Offline native tapper with save/copy/history. |
| Downloads | Terminal yt-dlp | Powerful but not production-session friendly. | Controlled queue with presets and output inbox. |
| Conversion | FFmpeg/online converters/misc apps | Scattered workflow, inconsistent output specs. | Cubase-oriented WAV presets and batch output. |
| Internal recording | System/third-party workarounds | Permission and routing friction. | Native app flow with explicit permission and WAV export. |

## Sources

- User prompt - repeated workflows and desired hub shape.
- https://www.beatsperminuteonline.com/?i=1 - Existing BPM tapper reference.
- https://github.com/yt-dlp/yt-dlp/blob/master/README.md - Downloader capabilities and dependency expectations.
- https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps - System audio capture approach.
- https://ffmpeg.org/ffmpeg.html - Conversion/post-processing tool behavior.

---
*Feature research for: Native macOS music-production utility hub*
*Researched: 2026-05-04*
