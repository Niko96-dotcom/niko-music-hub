# Phase 4: Internal Audio Recorder - Context

**Gathered:** 2026-05-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 4 delivers internal Mac/system audio recording that captures outgoing audio from processes or the system, writes it as a verified WAV PCM file matching the project audio preset (44.1 kHz, 24-bit stereo/preserve-mono), records the output in the shared output inbox, and makes it easy to reveal or drag into Cubase. It also establishes the permission guidance and failure-state taxonomy for the most privacy-sensitive tool in the app.

This phase does not implement screen capture, multi-track recording, live streaming, or Cubase project integration beyond file handoff.
</domain>

<decisions>
## Implementation Decisions

### Start Trigger
- **D-01:** Recording starts via a visible Start button in the recorder UI and optionally via a keyboard shortcut (Spacebar) when the recorder tool is active.
- **D-02:** The keyboard shortcut behavior mirrors BPM tapper conventions — Spacebar for primary action when the tool is focused.

### Live Feedback During Recording
- **D-03:** The UI shows live audio level meters during recording, giving the user visual confirmation that audio is being captured.
- **D-04:** Elapsed time is displayed alongside the meters so the user can estimate file size and duration.
- **D-05:** A single prominent Stop button ends the recording. Start becomes Stop while recording is active.

### Output File Naming
- **D-06:** Output files use an auto-generated timestamp name by default, formatted as `Recording YYYY-MM-DD HH-mm-ss.wav`.
- **D-07:** The user can optionally override the default name before starting recording (e.g., "Kick demo take 2").
- **D-08:** If the target filename already exists, auto-append a counter rather than overwriting.

### Max Recording Duration
- **D-09:** Recording is unlimited by default — the user stops when done.
- **D-10:** A configurable maximum duration setting exists in the app's recorder preferences, with a sensible default of 30 minutes.
- **D-11:** If the max duration is reached, recording stops automatically and the file is saved normally.

### Permission and Compatibility
- **D-12:** On launch, the app checks macOS version. Core Audio process taps require macOS 14.2+. If incompatible, the UI explains why and what the user can do (e.g., use an external audio interface).
- **D-13:** The app requests system audio recording permission and explains why clearly before any recording can begin.
- **D-14:** Silent permission failure is unacceptable — if permission is denied or restricted, the UI must tell the user exactly what to do.

### Output and Verification
- **D-15:** Recorded WAV files use the project audio preset (44.1 kHz, 24-bit, stereo/preserve-mono from Phase 3).
- **D-16:** `WAVOutputVerifier` (established in Phase 3) is reused to verify recorded output before adding it to the output inbox.
- **D-17:** Each output inbox item records the source tool ID, recording duration, and verified audio specs.
- **D-18:** Reveal in Finder and drag-out to Cubase work identically to Phase 3 conversion outputs.

### Failure States
- **D-19:** Permission errors are distinguishable from API errors (Core Audio tap failure) and output errors (write failure).
- **D-20:** Each failure type has a clear, actionable message with a recovery path.

### Claude's Discretion
- Exact meter animation style and refresh rate are flexible if they give meaningful real-time feedback.
- Exact preference UI (where max duration is set) is flexible — recorder settings panel or shared app settings.
- Exact permission dialog wording is flexible if it clearly explains why the app needs access and what happens if denied.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Scope And Requirements
- `.planning/ROADMAP.md` — Phase 4 goal, success criteria, planned slices, dependency on Phase 3, and phase boundary.
- `.planning/REQUIREMENTS.md` — REC-01 through REC-06 for recording permissions, capture, output, failure states, and handoff.
- `.planning/PROJECT.md` — Core value, audio capture constraint, permission constraint, file output constraint, and current project state.
- `.planning/STATE.md` — Current project status and accumulated decisions affecting Phase 4.

### Prior Architecture Decisions
- `.planning/phases/01-app-foundation-and-tool-architecture/01-CONTEXT.md` — Locked feature registry, shared `ToolContext`, output inbox, settings, job runner, and compact production-bench shell.
- `.planning/phases/02-bpm-tapper/02-CONTEXT.md` — Confirms the real-tool module pattern and compact SwiftUI feature surface.
- `.planning/phases/03-cubase-ready-wav-conversion/03-CONTEXT.md` — WAV preset (44.1 kHz, 24-bit, preserve-mono), WAVOutputVerifier, output inbox contract, external tool adapter pattern, and no-shell-interpolation rule.

### Research Guidance
- `.planning/research/ARCHITECTURE.md` — Ports/adapters pattern for audio capture, output inbox as product surface, job runner expectations.
- `.planning/research/STACK.md` — Core Audio process taps on macOS 14.2+, AVFAudio/AVFoundation for WAV writing, ScreenCaptureKit fallback context, and permission guidance.
- `.planning/research/PITFALLS.md` — Silent permission failure, generic error messages, and output drag-out pitfalls.

### Prior Key Decisions (from STATE.md)
- Core Audio system capture must be proven on the target Mac during recorder planning/execution.
- Helper tool packaging/licensing should be revisited before public distribution.
</canonical_refs>

## Existing Code Insights

### Reusable Assets
- `Sources/AppCore/Features/ToolFeature.swift` and `Sources/AppCore/Features/ToolRegistry.swift` — Feature boundary the recorder must use.
- `Sources/AppCore/Services/ToolContext.swift` — Provides settings, output inbox, job runner, file actions, and diagnostics.
- `Sources/AppCore/Settings/AudioPreset.swift` — Stores the shared audio preset (44.1 kHz, 24-bit, stereo/preserve-mono).
- `Sources/AppCore/OutputInbox/OutputInboxItem.swift` — Output item model for recording results.
- `Sources/AppCore/OutputInbox/JSONOutputInboxStore.swift` — Persists output items.
- `Sources/AppCore/Files/FileActions.swift` — Finder reveal behavior.
- `Sources/AppCore/Jobs/JobRunner.swift` — Shared job runner for recording progress and state.
- `Sources/AppCore/OutputInbox/OutputHandoff.swift` — Drag-out safety gate (only `.available` existing `.wav` files).
- `Sources/AppCore/Services/ExternalProcessRunning.swift` — External process runner (may be used if FFmpeg is involved in format bridging).
- `Sources/FeatureAudioConverter/WAVOutputVerifier.swift` — Reusable WAV verification for recorded output.
- `Sources/FeatureBPMTapper/BPMTapperView.swift` — Example compact SwiftUI tool surface with keyboard shortcut handling.

### Established Patterns
- The app is a Swift Package Manager macOS app targeting macOS 14.2+.
- Feature registration is static in `Sources/OutsideCubaseHub/AppComposition.swift`.
- Long-running work uses the shared job runner with progress, logs, and cancellation.
- Generated files are tracked as output inbox items with metadata, not just written to a folder.
- UI stays calm, compact, native, and action-oriented — no marketing or dashboard-style screens.

### Integration Points
- Add a recorder feature module, likely `FeatureAudioRecorder`, and register it in `AppComposition`.
- Mark recorder metadata with `.producesFiles` and `.runsJobs`.
- Read current `AppSettings.audioPreset` for WAV output specs.
- Add Core Audio tap capture behind a port (interface/abstract class) so the implementation is swappable.
- Write output through a WAV writer that uses the project preset.
- Run `WAVOutputVerifier` on the result before adding to the output inbox.
- Use `OutputHandoff` to gate reveal and drag-out.

</code_context>

<specifics>
## Specific Ideas

- Recording should feel immediate and responsive — no dialogs or setup steps between pressing record and capture starting.
- The UI should make the active recording state obvious from across the room (useful during live sessions).
- Auto-timestamp naming keeps files organized by session without requiring manual naming during flow.
- Configurable max duration prevents accidental multi-hour recordings that fill the disk.
</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within Phase 4 scope.

</deferred>

---

*Phase: 04-internal-audio-recorder*
*Context gathered: 2026-05-11*