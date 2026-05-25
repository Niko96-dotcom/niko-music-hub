# Phase 3: Cubase-Ready WAV Conversion - Context

**Gathered:** 2026-05-05T08:46:12+02:00
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 3 delivers the first file-producing audio utility in Outside Cubase Hub: a converter that accepts M4A, MP3, WAV, AIFF, and FLAC sources, converts them into verified WAV PCM output using the current project audio preset, records successful outputs in the shared output inbox, and makes them easy to reveal or drag into Cubase. It also establishes the preset-driven WAV pipeline that Phase 4 recording will reuse.

This phase does not implement waveform editing, trim/fade/sample-prep chains, BPM/key/loudness analysis, recursive sample-pack ingestion, downloader behavior, internal audio recording, or Cubase project-folder watching.

</domain>

<decisions>
## Implementation Decisions

### Project WAV Preset
- **D-01:** The default Cubase-ready audio preset is 44.1 kHz, 24-bit, stereo.
- **D-02:** The existing app default should match that preset. During discussion, `Sources/AppCore/Settings/AudioPreset.swift` was updated from 48 kHz to 44.1 kHz, with the corresponding settings test assertion updated.
- **D-03:** Mono source files should stay mono in converted output. Stereo sources stay stereo.
- **D-04:** Conversion should always match the selected preset for sample rate and bit depth.
- **D-05:** If output verification fails, mark that conversion failed and keep the source untouched. Do not treat a questionable WAV as ready for Cubase.

### Batch Conversion Flow
- **D-06:** Phase 3 accepts M4A, MP3, WAV, AIFF, and FLAC as the v1 common-audio source set.
- **D-07:** Dropped folders should scan top-level audio files only. Do not recurse into subfolders in Phase 3.
- **D-08:** Use native conversion first, then fall back to FFmpeg when native conversion is unsupported or fails.
- **D-09:** If FFmpeg is missing and a file needs fallback, fail only that file with helper guidance. Continue native-convertible files in the batch.
- **D-10:** Cancellation should cancel remaining files while allowing the current file to finish safely, avoiding half-written ready outputs.

### Output Handoff
- **D-11:** Converted files should use the source filename plus a preset suffix by default, such as `Kick Loop - 44100Hz 24bit.wav`.
- **D-12:** If the target filename already exists, auto-append a counter rather than overwriting or failing the file.
- **D-13:** Each output inbox item should record the source file, verified output specs, and converter used.
- **D-14:** Drag-out should work from both converter results and the shared output inbox.

### the agent's Discretion
- Exact UI layout is flexible if the converter remains compact, native, and production-bench-like.
- Exact metadata key names are flexible if source file, verified specs, and converter used are clearly recorded.
- Exact temporary-file and cleanup strategy is flexible, but partial or unverified files must not appear as ready outputs.
- Exact native conversion coverage and FFmpeg fallback detection are implementation details for research/planning, but the adapter boundary and no-shell-interpolation rule are locked.
- Exact per-file progress granularity is flexible if batch conversion shows per-file progress, success, failure, and recoverable error states.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Scope And Requirements
- `.planning/ROADMAP.md` - Phase 3 goal, success criteria, planned slices, dependency on Phase 2, and phase boundary.
- `.planning/REQUIREMENTS.md` - CONV-01 through CONV-05 plus UX-01 and UX-02 reveal/drag-out expectations.
- `.planning/PROJECT.md` - Core value, native macOS constraint, file output constraint, conversion constraint, helper-tool boundary, and current project state.
- `.planning/STATE.md` - Current project status and accumulated decisions affecting Phase 3.

### Prior Architecture Decisions
- `.planning/phases/01-app-foundation-and-tool-architecture/01-CONTEXT.md` - Locked feature registry, shared `ToolContext`, output inbox, settings, job runner, and compact production-bench shell.
- `.planning/phases/02-bpm-tapper/02-CONTEXT.md` - Confirms the real-tool module pattern and compact SwiftUI feature surface established after Phase 1.

### Research Guidance
- `.planning/research/ARCHITECTURE.md` - Converter data flow, ports/adapters pattern, output inbox as product surface, and job runner expectations.
- `.planning/research/FEATURES.md` - Conversion MVP, output inbox dependency, project preset dependency, and deferred sample-prep ideas.
- `.planning/research/PITFALLS.md` - WAV output mismatch, unsafe external-tool commands, generic error messages, and output drag-out pitfalls.
- `.planning/research/STACK.md` - AVFAudio/AVFoundation native conversion, FFmpeg fallback, UniformTypeIdentifiers, XCTest, and helper-tool guidance.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Sources/AppCore/Features/ToolFeature.swift` and `Sources/AppCore/Features/ToolRegistry.swift` define the feature boundary the converter must use.
- `Sources/AppCore/Services/ToolContext.swift` provides settings, output inbox, job runner, file actions, and diagnostics to feature views.
- `Sources/AppCore/Settings/AudioPreset.swift` stores the shared audio preset. It now defaults to 44.1 kHz, 24-bit, 2-channel stereo.
- `Sources/AppCore/Settings/AppSettings.swift` persists the shared output folder, audio preset, and helper tool paths.
- `Sources/AppCore/Settings/HelperToolSettings.swift` already has optional `ffmpeg` and `ffprobe` paths for fallback conversion and metadata probing.
- `Sources/AppCore/Jobs/JobRunner.swift` supports queued, running, completed, failed, canceled, progress, messages, logs, and cancellation.
- `Sources/AppCore/OutputInbox/OutputInboxItem.swift` provides file URL, source tool ID, status, and string metadata for generated outputs.
- `Sources/AppCore/OutputInbox/JSONOutputInboxStore.swift` can add, update, list, and refresh output availability.
- `Sources/AppCore/Files/FileActions.swift` and the app target's `AppKitFileActions` provide Finder reveal behavior.
- `Sources/FeatureBPMTapper/BPMTapperFeature.swift` and `Sources/FeatureBPMTapper/BPMTapperView.swift` are the closest real feature examples for metadata, view construction, focused controls, and compact styling.

### Established Patterns
- The app is a Swift Package Manager macOS app targeting macOS 14.2.
- Shared contracts live in `AppCore`; feature-specific use cases and UI should live in a feature module.
- Feature registration is static in `Sources/OutsideCubaseHub/AppComposition.swift`.
- Long-running work should use the shared job runner instead of feature-local progress systems.
- Generated files should be tracked as output inbox items, not merely written to a folder.
- UI should stay calm, compact, native, and action-oriented, avoiding marketing or dashboard-style screens.

### Integration Points
- Add a converter feature module, likely `FeatureAudioConverter`, and register it in `AppComposition`.
- Mark converter metadata with `.producesFiles` and `.runsJobs`.
- Read the current `AppSettings.audioPreset` and `outputFolder` before converting.
- Add conversion use cases behind an audio converter port, with AVFoundation/AVFAudio and FFmpeg adapters outside the SwiftUI view.
- Add output inbox items only after successful WAV metadata verification.
- Extend file actions or output views as needed for drag-out from converter results and the output inbox.

</code_context>

<specifics>
## Specific Ideas

- The default conversion target should reflect the user's usual Cubase projects: 44.1 kHz, 24-bit, stereo.
- Output filenames should visibly communicate the preset, for example `Kick Loop - 44100Hz 24bit.wav`.
- The converter should be useful for a practical producer batch: M4A, MP3, WAV, AIFF, and FLAC.
- Failed or unverified files should not be presented as ready to drag into Cubase.

</specifics>

<deferred>
## Deferred Ideas

None - discussion stayed within Phase 3 scope.

</deferred>

---

*Phase: 03-cubase-ready-wav-conversion*
*Context gathered: 2026-05-05T08:46:12+02:00*
