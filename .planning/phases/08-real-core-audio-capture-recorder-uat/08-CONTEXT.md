# Phase 8: Real Core Audio Capture & Recorder UAT - Context

**Gathered:** 2026-05-23
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous — recommendations accepted)

<domain>
## Phase Boundary

Replace the synthetic `CoreAudioTapAdapter` path with real macOS 14.2+ Core Audio process taps (system-wide mixdown), wire buffers through `WAVRecorderWriter` at the Cubase preset, fix recorder start/stop UX, and produce `VERIFICATION.md` for REC-01–REC-06 with documented permission-skip policy.

</domain>

<decisions>
## Implementation Decisions

### Capture scope & API
- System-wide capture via `CATapDescription` with empty `processes`, `isMixdown = true`, stereo (`isMono = false`), private tap, unmuted output.
- Chain: `AudioHardwareCreateProcessTap` → private aggregate device with default output as main sub-device → `AudioDeviceCreateIOProcIDWithBlock` → `AVAudioConverter` → `WAVRecorderWriter`.
- Gate compatibility at macOS 14.2+ (major/minor), not 14.0 only.

### Permission & packaging
- Keep `AVCaptureDevice` audio permission flow (matches Phase 4); add `NSAudioCaptureUsageDescription` to `script/build_and_run.sh` generated Info.plist for distributed `.app` runs.
- Permission denied / restricted / API failures surface existing `RecorderError` + `StandardErrorCard` paths — no silent failure.

### Recorder UX (REC-04)
- `AudioRecorderViewModel` runs capture on a `Task`: consumes `AsyncStream<RecorderAudioLevel>` for meter + elapsed time; `stopRecording()` calls `capturePort.stopRecording()` then finalizes inbox handoff.
- `RecordSystemAudioUseCase` exposes URL resolution only; live record/stop goes through the port (use case `execute` remains for tests).

### Verification
- Automated tests keep `XCTSkip` when system audio permission unavailable; integration tests exercise real tap when authorized.
- `VERIFICATION.md` status `human_needed` for target-hardware proof (play audio during record, drag to Cubase).

### Claude's Discretion
- Exact aggregate device dictionary keys and converter priming if tap format differs from preset.
- Whether to add non-silent PCM heuristic in tests (optional; human UAT is authoritative for “real audio”).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `WAVRecorderWriter`, `WAVOutputVerifier`, `AudioCapturePort`, `RecordSystemAudioUseCase`, `AudioRecorderViewModel` / `AudioRecorderView`.
- Phase 3 inbox + handoff patterns from converter.

### Established Patterns
- Feature boundary: `CoreAudioTapAdapter` implements `AudioCapturePort`.
- Errors: `RecorderError` + `StandardErrorCard` in recorder view.
- Tests: permission-gated skips via `requireRecordingPermission`.

### Integration Points
- `CoreAudioTapAdapter` — replace synthetic loop and `writeSilenceWAV`.
- `AudioRecorderViewModel` — fix start/stop task wiring.
- `script/build_and_run.sh` — Info.plist usage description.

</code_context>

<specifics>
## Specific Ideas

Follow Apple’s “Capturing system audio with Core Audio taps” sample and audiotee-style aggregate device setup. Do not mute system audio during capture.

</specifics>

<deferred>
## Deferred Ideas

- Per-process picker UI (tap specific app only) — out of scope; system-wide is enough for v1.1.
- ScreenCaptureKit fallback — only if Core Audio taps fail on target hardware.

</deferred>
