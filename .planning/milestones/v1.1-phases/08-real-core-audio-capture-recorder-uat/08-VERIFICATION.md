---
phase: "08"
name: "real-core-audio-capture-recorder-uat"
status: human_needed
completed: "2026-05-23"
requirements: ["REC-01", "REC-02", "REC-03", "REC-04", "REC-05", "REC-06"]
---

## Phase 8 Verification: Real Core Audio Capture & Recorder UAT

### Summary

Replaced synthetic `CoreAudioTapAdapter` with `SystemAudioProcessTapSession` (Core Audio process tap + aggregate device + IO proc). Recorder view model now streams real levels/elapsed time and supports stop. `NSAudioCaptureUsageDescription` added to `script/build_and_run.sh` app bundle plist.

---

## Automated Evidence

| Requirement | Evidence |
|-------------|----------|
| REC-01 | `isCompatibleMacOS()` gates 14.2+; permission UI + incompatible section in `AudioRecorderView` |
| REC-02 | `SystemAudioProcessTapSession` uses `AudioHardwareCreateProcessTap` / aggregate device (not random noise) |
| REC-03 | `WAVRecorderWriter` + tap PCM via `AVAudioConverter`; `CoreAudioTapAdapterTests` write WAV at preset |
| REC-04 | `AudioRecorderViewModel` Task consumes `AsyncStream<RecorderAudioLevel>`; Spacebar stop in view |
| REC-05 | `RecorderError` paths + `StandardErrorCard`; tap failures → `apiError` with OSStatus context |
| REC-06 | Save confirmation Reveal/Open; inbox `addItem` on finalize (same as Phase 4) |

### Test suite

```
scripts/test.sh — 153 executed, 0 failures, 6 skipped (system audio permission)
```

Permission-gated: `CoreAudioTapAdapterTests`, `RecorderIntegrationTests` (XCTSkip when not authorized).

---

## Human Verification (target Mac, macOS 14.2+)

- [ ] Grant system audio recording permission when prompted.
- [ ] Play music or Cubase output; record 10s; WAV contains audible content (not silence-only).
- [ ] Stop via button and Spacebar; elapsed time and meter move during capture.
- [ ] Reveal saved WAV; drag into Cubase or Finder.
- [ ] Deny permission → explicit guidance, no silent failure.

---

## Permission skip policy

Integration tests call `requireRecordingPermission` and `XCTSkip` when `AVCaptureDevice` audio authorization is not `.authorized`. CI/agents without permission rely on human UAT above.
