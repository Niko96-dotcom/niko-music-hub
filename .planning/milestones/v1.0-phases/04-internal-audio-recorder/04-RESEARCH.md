# Phase 4: Internal Audio Recorder - Research

**Researched:** 2026-05-11
**Phase:** 04-internal-audio-recorder
**Confidence:** HIGH for Swift/AVFAudio, MEDIUM for Core Audio tap API details

---

## Domain Overview

Phase 4 is the highest-risk OS integration in the project. The goal is to capture internal Mac/system audio (not microphone input) and write it as a verified WAV PCM file matching the project's audio preset (44.1 kHz, 24-bit stereo/preserve-mono). The recorder must work with the existing output inbox, job runner, and WAVOutputVerifier from Phase 3.

---

## Core Audio Process Tap API

### Background

Apple's **Core Audio process taps** (introduced macOS 14.2) allow capturing audio output from specific apps or the entire system without requiring a virtual audio device like BlackHole. This is distinct from ScreenCaptureKit which captures audio as part of screen recording.

### Key API Points

The primary API for system audio capture on macOS 14.2+ is `OAudioTap` (Objective-C++). The tap is attached to an audio process (or the system process for all-audio) and provides audio buffers via a callback. Important considerations:

1. **OAudioTap requires macOS 14.2 minimum** - must gate with version check
2. **Requires `NSAudioCaptureUsageDescription` in Info.plist** - explains why to user
3. **Requires user permission** via `AVCaptureDevice.requestAccess(for: .audio)` or `CGRequestFlexibilityAccess()`
4. **System audio recording permission** is separate from microphone permission

### Tap Attachment Points

- **Per-process tap**: Attach to a specific app's audio output (e.g., Cubase itself)
- **System-wide tap**: Attach to the "owning" process representing all audio output (requires special entitlement)

For this app, system-wide capture is likely what's needed. Per-project docs indicate:
- The user wants to capture "internal/system audio" not a specific app's output
- This means the tap needs to be on the host audio server process

### Capture Flow

```
1. Check macOS version >= 14.2 (else show incompatible UI)
2. Check/request system audio recording permission
3. Create OAudioTap on system audio process
4. Start tap → audio buffers flow via callback
5. Write buffers to AVAudioPCMBuffer
6. Periodically flush to AVAudioFile (WAV writer)
7. Stop tap → finalize WAV → verify → add to inbox
```

---

## Permission Flow

### Required Entries

**Info.plist:**
```xml
<key>NSAudioCaptureUsageDescription</key>
<string>Outside Cubase Hub needs access to record your Mac's internal audio so you can import recordings directly into Cubase.</string>
```

### Permission Detection

Use `AVCaptureDevice.requestAccess(for: .audio)` to trigger the system permission dialog. Check `AVCaptureDevice.authorizationStatus(for: .audio)` for current state:
- `.authorized` → proceed
- `.denied` → show guidance to System Settings > Privacy & Security
- `.notDetermined` → call requestAccess and handle async response
- `.restricted` → show device restriction message

### Silent Failure Prevention

Per PITFALLS.md: "Silent permission failure is unacceptable." The UI must:
1. Show exact permission status on launch
2. Explain precisely what to do if denied (open System Settings)
3. Never proceed silently when permission is denied

---

## WAV Writing Pipeline

### Existing Assets (Phase 3)

- `AudioPreset.swift` - stores 44.1 kHz, 24-bit, stereo/preserve-mono configuration
- `WAVOutputVerifier.swift` - verifies sample rate, bit depth, channel count, and PCM format
- `OutputInboxItem.swift` - models output item with metadata
- `JSONOutputInboxStore.swift` - persists items

### Writing Flow

```swift
// 1. Create AVAudioFile with AudioPreset settings
let format = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: preset.sampleRate,  // 44100.0
    channels: preset.channels,      // 2 (stereo) or 1 (mono)
    interleaved: false
)!
let outputFile = try AVAudioFile(
    forWriting: outputURL,
    settings: format.settings
)

// 2. Write buffers from tap callback
func audioTapCallback(buffer: AVAudioPCMBuffer) {
    try outputFile.write(from: buffer)
}

// 3. On stop: flush and verify
try outputFile.flush()
WAVOutputVerifier.verify(outputURL, against: preset)  // From Phase 3
```

### Output File Naming

- Default: `Recording YYYY-MM-DD HH-mm-ss.wav`
- Optional override before recording starts
- Counter append if file exists: `Recording YYYY-MM-DD HH-mm-ss (1).wav`

### Max Duration

- Configurable max duration in settings (default 30 minutes)
- Auto-stop when max reached, save file normally
- Timer runs on `JobRunner` with cancellation support

---

## Failure State Taxonomy

| Failure Type | Cause | User Message | Recovery |
|---|---|---|---|
| Permission Denied | User rejected system audio permission | "Recording requires system audio permission. Open System Settings > Privacy & Security to allow." | Button opens System Settings |
| Permission Restricted | MDM or parental controls | "System audio recording is restricted on this device." | Show restriction notice |
| API Failure | OAudioTap returned error | "Audio capture failed. Core Audio tap error: [details]. Try restarting your Mac." | Offer retry |
| Write Failure | Disk full or path not writable | "Could not save recording. Check available disk space and output folder." | Check disk space, change folder |
| Verification Failure | WAVOutputVerifier rejected output | "Recording failed validation. The file may be corrupted." | Offer to delete and retry |
| Incompatible macOS | Version < 14.2 | "Recording requires macOS 14.2 or later. Current: [version]" | Show what they can do |

Each state is distinguishable and recoverable where possible.

---

## Live Metering

### Audio Level Extraction

From `AVAudioPCMBuffer`, peak and average levels can be computed from the float channel data:

```swift
func computeLevels(from buffer: AVAudioPCMBuffer) -> (peak: Float, average: Float) {
    guard let channelData = buffer.floatChannelData else { return (0, 0) }
    let channelCount = Int(buffer.format.channelCount)
    let frameLength = Int(buffer.frameLength)
    var peak: Float = 0
    var sum: Float = 0
    for ch in 0..<channelCount {
        for frame in 0..<frameLength {
            let sample = abs(channelData[ch][frame])
            peak = max(peak, sample)
            sum += sample
        }
    }
    let average = sum / Float(frameLength * channelCount)
    return (peak, average)
}
```

### UI Display

- Peak meter: per-channel or combined, updates at ~30 Hz
- Elapsed time: `HH:MM:SS` format
- Recording indicator: pulsing red dot or animated border

---

## Port/Adapter Pattern

### AudioCapturePort Protocol

```swift
protocol AudioCapturePort {
    var isRecording: Bool { get async }
    func requestPermission() async -> PermissionResult
    func startRecording(config: RecordingConfig) async throws -> AsyncStream<AudioLevel>
    func stopRecording() async throws -> RecordingResult
}

struct RecordingConfig {
    let outputURL: URL
    let preset: AudioPreset
    let maxDuration: TimeInterval?  // nil = unlimited
}

struct AudioLevel {
    let peak: Float
    let average: Float
    let elapsedTime: TimeInterval
}

enum PermissionResult {
    case authorized
    case denied(needsSettings: Bool)
    case restricted
}

enum RecordingResult {
    case success(URL, Duration, AudioSpecs)
    case failure(RecorderError)
}
```

### Core Audio Adapter

`CoreAudioTapAdapter` implements `AudioCapturePort` using `OAudioTap`. Behind the adapter, the actual tap creation and callback wiring lives here — swappable if Apple changes APIs.

---

## Architecture Integration Points

### Feature Registration

```
FeatureRecorder (new)
├── AudioRecorderFeature: ToolFeature
│   ├── id: "audio-recorder"
│   ├── capability: [.producesFiles, .runsJobs]
│   └── makeView(context: ToolContext) → AnyView
├── AudioRecorderViewModel (MainActor)
├── RecordSystemAudioUseCase
├── CoreAudioTapAdapter (implements AudioCapturePort)
└── WAVWriter (handles buffering + file output)
```

### Job Runner Integration

Recording uses the shared `JobRunner` for:
- Progress: elapsed time, current level, bytes written
- Cancellation: stop tap cleanly
- Logs: errors, permission events, file finalization
- State: `recording` job state with metadata

### Output Inbox Integration

On successful recording:
1. `WAVOutputVerifier.verify(outputURL, against: preset)` must pass
2. Create `OutputInboxItem` with:
   - `toolID: .audioRecorder`
   - `sourceURL: outputURL`
   - `duration: recordedDuration`
   - `audioSpecs: AudioSpecs(sampleRate: 44100, bitDepth: 24, channels: 2)`
3. `JSONOutputInboxStore.append(item)`
4. File is now revealable and drag-out ready via `OutputHandoff`

---

## Phase 4 Specific Considerations

### 04-01: Core Audio Tap Proof and Permission Flow

This plan establishes:
- macOS version gate (14.2+)
- Permission request and detection
- Minimal tap-to-WAV proof (5 seconds of silence/system audio)
- Verification that the output is a real playable WAV

### 04-02: WAV Writer Integration with Project Preset

Builds on 04-01 to:
- Connect tap output to AVAudioFile writer
- Use `AudioPreset` (44.1 kHz, 24-bit) from Phase 3
- Handle real-time buffer flushing
- Auto-stop at max duration
- Reuse `WAVOutputVerifier` from Phase 3

### 04-03: Recorder UI and Failure States

Builds on 04-02 to:
- Add Start/Stop button with Spacebar shortcut
- Add live audio meters and elapsed time display
- Add configurable max duration setting
- Add failure state display (permission/API/output with distinct recovery)
- Add filename override option

### 04-04: Manual Verification Against Real System Audio

Final verification:
- Record actual system audio (not silence)
- Play back in QuickTime/VLC to confirm it's real audio
- Import into Cubase as a real test
- Verify meter levels during recording

---

## Key Risks

1. **OAudioTap API gaps**: Apple's process tap API for system audio capture is less documented than AVCaptureDevice; verify on target Mac
2. **Permission UX on Sonoma+**: System audio recording permission flow changed in macOS 14; need to test exact dialog and settings path
3. **Disk space during long recordings**: 44.1kHz/24-bit stereo = ~15 MB/minute; warn at low disk space and auto-stop at very low

---

## Sources

- https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps
- https://developer.apple.com/documentation/avfaudio/avaudiofile
- https://developer.apple.com/documentation/avfaudio/avaudiopcmbuffer
- `.planning/phases/03-cubase-ready-wav-conversion/03-CONTEXT.md` — WAVOutputVerifier and AudioPreset reuse
- `.planning/research/ARCHITECTURE.md` — Ports/adapters pattern for audio capture

---

*Phase: 04-internal-audio-recorder*
*Research: Initial planning research*