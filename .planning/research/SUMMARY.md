# Project Research Summary

**Project:** Outside Cubase Hub
**Domain:** Native macOS music-production utility hub
**Researched:** 2026-05-04
**Confidence:** MEDIUM-HIGH

## Executive Summary

Outside Cubase Hub should be built as a native macOS utility hub, not a web app or generic file converter. The app's product value is speed and trust during a production session: tap a tempo, capture internal audio, convert/download a source, and drag the result into Cubase without opening a browser or Terminal.

The recommended technical approach is Swift/SwiftUI with small AppKit bridges, a feature registry, shared job/output services, and adapter boundaries around Core Audio, AVFAudio, FFmpeg, and yt-dlp. The riskiest feature is internal system audio capture, so the roadmap should validate real audio-to-WAV capture before investing too much in recorder polish.

The main product risk is scope creep into "mini DAW" territory. The app should stay a clean bench of focused tools that produce Cubase-ready files.

## Key Findings

### Recommended Stack

Use native Swift with SwiftUI/AppKit for the shell, Core Audio process taps for audio-only system capture on macOS 14.2+, AVFAudio/AVFoundation for native audio IO, FFmpeg for broader conversion fallback, and yt-dlp as a controlled external downloader adapter.

**Core technologies:**
- Swift/SwiftUI: native app and UI shell - best fit for local macOS workflows.
- Core Audio taps: system/process audio capture - best fit for audio-only recording.
- AVFAudio: WAV/native audio read-write - keeps common conversion paths native.
- FFmpeg: fallback conversion/post-processing - broad codec coverage.
- yt-dlp: URL download backend - mature support across many websites.

### Expected Features

**Must have (table stakes):**
- BPM tapper - replaces the existing web tapper.
- Internal audio recording to WAV - direct requested workflow.
- M4A/common audio to WAV conversion - direct requested workflow.
- Website downloader queue - direct requested workflow.
- Output inbox - makes generated files easy to drag into Cubase.
- Tool health checks - avoids mysterious helper-tool failures.
- Modular feature shell - supports future tool ideas.

**Should have (competitive):**
- Cubase project preset for sample rate/bit depth/channel defaults.
- Naming templates and source notes.
- Clipboard URL intake.
- Simple trim/fade/sample-prep chain after base conversion works.

**Defer (v2+):**
- Automatic BPM/key/loudness analysis.
- Stem separation or AI cleanup.
- Cubase project watcher or direct DAW integration.

### Architecture Approach

Use a feature-registry architecture with thin SwiftUI feature views, pure use cases, protocol service ports, and infrastructure adapters. All long-running work should go through a shared job runner, and all generated files should go to a shared output inbox with metadata and drag/reveal actions.

**Major components:**
1. App Shell - navigation, settings, shared jobs, output inbox.
2. Feature Registry - declares tools without hard-coding the shell.
3. Use Cases - BPM, convert, record, download behavior.
4. Service Ports - stable interfaces for audio, downloads, files, diagnostics.
5. Adapters - Core Audio, AVAudioFile, FFmpeg, yt-dlp.
6. Output Inbox - local file metadata and Cubase handoff.

### Critical Pitfalls

1. **System audio capture fails late** - prove capture-to-WAV early.
2. **External commands become unsafe/untestable** - use `Process` with argv arrays behind adapters.
3. **WAV output is not Cubase-friendly** - inspect output headers and use presets.
4. **Feature hub becomes hard-coded** - create registry before the tools pile up.
5. **Downloader trust/legal boundary blurs** - explicit URL workflow and rights-aware scope.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: App Foundation and Tool Architecture
**Rationale:** The user's strongest architectural requirement is easy feature addition.
**Delivers:** Native app skeleton, feature registry, job runner, output inbox, settings foundation.
**Addresses:** Feature modularity and future extensibility.
**Avoids:** Hard-coded dashboard debt.

### Phase 2: BPM Tapper
**Rationale:** Low-risk, immediately useful, validates feature-module shape.
**Delivers:** Offline BPM tapper with reset, half/double, copy/save/history.
**Uses:** App shell and feature registry from Phase 1.

### Phase 3: Cubase-Ready WAV Conversion
**Rationale:** Establishes the WAV/output pipeline needed by both converter and recorder.
**Delivers:** Drag/drop M4A/common audio conversion to WAV with presets and output validation.
**Uses:** AVFAudio first, FFmpeg fallback adapter.

### Phase 4: Internal Audio Recorder
**Rationale:** Highest technical risk and core requested value.
**Delivers:** Permission flow, internal audio capture, record/stop controls, WAV export.
**Uses:** Core Audio tap adapter, output inbox, WAV preset pipeline.

### Phase 5: Downloader Hub
**Rationale:** Depends on job runner, output inbox, and safe external-tool adapter patterns.
**Delivers:** URL input, yt-dlp tool health, download jobs, progress/errors, output handoff.
**Uses:** Safe process adapter and shared job model.

### Phase 6: Integration Polish and Extensibility Check
**Rationale:** Verify the hub feels coherent and remains easy to extend.
**Delivers:** Keyboard shortcuts, final output actions, error polish, dummy feature/extensibility verification.

### Phase Ordering Rationale

- Build the feature architecture before multiple tools create coupling.
- Ship BPM early because it is quick user value and proves the shell.
- Build conversion before recording so WAV output and presets are solved once.
- Validate internal audio capture before downloader polish because it carries the highest OS/API risk.
- Add downloader after process-adapter patterns exist from FFmpeg.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 3:** Exact native conversion coverage and WAV bit-depth handling.
- **Phase 4:** Core Audio tap implementation details, permission behavior, and fallback strategy.
- **Phase 5:** yt-dlp progress parsing, helper update policy, and licensing/distribution choice.

Phases with standard patterns:
- **Phase 1:** Standard SwiftUI app architecture with testable modules.
- **Phase 2:** BPM tapper math and UI are straightforward.
- **Phase 6:** Integration/polish should be driven by implemented behavior.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Official Apple docs and local tool versions support the direction. |
| Features | MEDIUM-HIGH | User supplied concrete repeated workflows; extras are inferred from production workflow needs. |
| Architecture | HIGH | Feature registry + ports/adapters directly answers extensibility requirement. |
| Pitfalls | MEDIUM-HIGH | Audio capture and helper packaging are known risk areas and should be proven. |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **Audio capture exact implementation:** Validate Core Audio process tap behavior on the target Mac during Phase 4 planning/execution.
- **Distribution model:** Decide later whether this remains a local personal app, bundled helper app, or notarized public app.
- **Cubase-specific WAV defaults:** Confirm the user's usual project sample rate/bit depth after initial implementation.

## Sources

### Primary (HIGH confidence)

- https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps - Core Audio system capture direction.
- https://developer.apple.com/documentation/ScreenCaptureKit/capturing-screen-content-in-macos - Screen/audio capture fallback context.
- https://developer.apple.com/documentation/avfaudio/avaudiofile - Native audio file read/write.
- https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox - macOS file access constraints.
- https://github.com/yt-dlp/yt-dlp/blob/master/README.md - yt-dlp install/dependency behavior.
- https://ffmpeg.org/ffmpeg.html - FFmpeg conversion behavior.

### Secondary (MEDIUM confidence)

- User-provided workflow examples and desired feature list.
- Existing online BPM tapper usage as a product reference.

---
*Research completed: 2026-05-04*
*Ready for roadmap: yes*
