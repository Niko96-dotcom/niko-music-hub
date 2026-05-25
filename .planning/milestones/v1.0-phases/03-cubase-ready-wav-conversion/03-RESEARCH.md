# Phase 03 - Research

**Phase:** 03 - Cubase-Ready WAV Conversion
**Researched:** 2026-05-05
**Mode:** Inline GSD phase research
**Confidence:** HIGH for app architecture and adapter boundaries, MEDIUM-HIGH for exact native format coverage until implementation verifies real files on the target Mac

## Research Objective

Answer: what do we need to know to plan Phase 3 well?

Phase 3 is the first file-producing real tool in Outside Cubase Hub. The plan has to protect three things at once:

- WAV output must be Cubase-ready, not merely "some WAV".
- Native conversion should be tried first, with FFmpeg isolated behind a safe adapter.
- Verified outputs must flow into the existing output inbox and be revealable/draggable into Cubase.

## Source Inputs

| Source | Relevant planning signal |
|--------|--------------------------|
| `.planning/phases/03-cubase-ready-wav-conversion/03-CONTEXT.md` | Locked decisions D-01 through D-14: preset defaults, supported file set, fallback rules, safe cancellation, naming, metadata, and drag-out. |
| `.planning/phases/03-cubase-ready-wav-conversion/03-UI-SPEC.md` | Compact SwiftUI converter surface, batch rows, status copy, `Convert to WAV`, `Stop After Current File`, `Choose FFmpeg`, reveal, and drag-out contracts. |
| `.planning/REQUIREMENTS.md` | CONV-01 through CONV-05 plus UX-01 and UX-02 must be covered by plans. |
| `Sources/AppCore` | Existing settings, helper tool paths, job runner, output inbox, feature registry, and file actions. |
| `Sources/FeatureBPMTapper` | Closest real feature module pattern for registration, top-leading SwiftUI surface, view model tests, and local feature services. |

## Technical Findings

### Native AVFAudio Path

Apple's AVFAudio stack gives the right shape for a streaming native conversion path:

- `AVAudioFile` reads and writes sequentially through `AVAudioPCMBuffer`.
- `AVAudioFormat` exposes sample rate, channel count, common format, and settings needed to construct processing and output formats.
- `AVAudioConverter` performs format conversion including sample-rate and PCM representation transforms.

Planning consequence: the native converter should not load entire files into memory. It should open the source file, stream buffers through `AVAudioConverter`, write to a temporary WAV, then verify the final file before moving it into the ready output path.

### WAV Spec Verification

AVAudioFile can reopen the output and expose on-disk `fileFormat` values. For Phase 3, verification should check:

- output file exists and is non-empty;
- file type is WAV / linear PCM;
- sample rate equals selected preset sample rate, such as `44100`;
- bit depth equals selected preset bit depth, such as `24`;
- channel count matches the channel handling policy;
- the verified file only enters the output inbox after all checks pass.

Planning consequence: verification belongs in a reusable service, not only in UI status strings. Phase 4 recording will reuse this contract.

### Channel Handling

The phase context locks the default music-production target to 44.1 kHz, 24-bit, and stereo-oriented Cubase output, but also locks the behavior that mono sources stay mono and stereo sources stay stereo.

Planning consequence: `AudioPreset` needs a concrete channel policy such as `preserveMonoStereo`, `mono`, and `stereo`. For default display, the UI can show `44.1 kHz - 24-bit - Preserve mono/stereo`, while stereo sources still produce stereo WAVs and mono sources produce mono WAVs.

### FFmpeg Fallback

FFmpeg should be a fallback adapter, not a view concern. The command must be built as executable URL plus argument array, never shell interpolation. For 24-bit WAV, the adapter should use an explicit PCM codec such as `pcm_s24le`; for 16-bit, `pcm_s16le`; for 32-bit, either a deliberate supported path or a rejected unsupported preset until implemented.

Example argv shape for a 24-bit stereo 44.1 kHz output:

```text
ffmpeg -hide_banner -nostdin -y -i source.m4a -vn -ar 44100 -ac 2 -c:a pcm_s24le output.tmp.wav
```

Planning consequence: tests should assert argv arrays exactly and source-scan for `/bin/sh`, `sh -c`, and string-built command execution.

### Helper Health

`HelperToolSettings` already stores optional `ffmpeg`, `ffprobe`, and `ytDlp` URLs. Phase 3 should use the `ffmpeg` setting for conversion fallback and expose missing-helper recovery per file. If FFmpeg is missing, only the affected file fails with `Choose FFmpeg`; native-convertible files continue.

Planning consequence: add a small FFmpeg health checker and a row-level missing-helper state. Do not block the whole batch just because one fallback file needs FFmpeg.

### Batch Jobs And Cancellation

The existing `JobRunner` already has queued/running/completed/failed/canceled states and progress messages. Phase 3's `Stop After Current File` requirement is more specific than immediate task cancellation: it should finish the active conversion safely and skip remaining queued rows.

Planning consequence: the batch use case needs its own "stop after current" controller checked between files. Avoid calling `cancelJob` in a way that interrupts the active file and risks a half-written ready output.

### Drag-In And Drag-Out

SwiftUI supports file drops through `onDrop` and file choosing through native file import/open panel patterns. `UniformTypeIdentifiers` should describe accepted file URLs and supported audio types. Drag-out should only be available for verified, existing WAV file URLs. Pending, failed, skipped, missing, or unverified rows must not provide the same drag item.

Planning consequence: implement drag eligibility as a testable helper and use it in both converter result rows and `OutputInboxInspectorView`.

## Recommended Implementation Slices

| Plan | Slice | Why first/next |
|------|-------|----------------|
| 03-01 | Audio preset/channel policy, conversion request/result model, native converter, WAV verifier, output naming. | Establishes the reusable WAV pipeline and verification contract before UI. |
| 03-02 | FFmpeg health and fallback adapter with safe argv tests. | Contains the external-tool risk behind a service boundary. |
| 03-03 | Batch converter feature registration, intake, view model, SwiftUI surface, job integration, output inbox writes. | Turns the services into the user-visible converter workflow. |
| 03-04 | Reveal and drag-out from converter rows plus shared output inbox. | Completes the Cubase handoff requirements and shared file surface. |

## Validation Architecture

Use XCTest through Swift Package Manager. The phase should create `FeatureAudioConverter` and `FeatureAudioConverterTests`, with AppCore tests extended where shared output inbox/file actions change.

Recommended commands:

- Focused converter tests: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter FeatureAudioConverterTests`
- AppCore handoff tests: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter AppCoreTests`
- Full suite: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`

Validation dimensions:

1. Domain model tests for preset channel policy, supported file filtering, output naming, and collision counters.
2. Native converter tests using generated short PCM fixtures and AVAudioFile verification where feasible.
3. FFmpeg adapter tests with fake process runner, exact argv assertions, and no-shell source scans.
4. Batch use case tests for mixed success/failure, missing FFmpeg fallback, stop-after-current, and output inbox writes only after verification.
5. UI/view model tests for drag/choose intake states, row states, and action availability.
6. Manual smoke for real drag-in, conversion, reveal, and drag-out into Finder/Cubase-compatible targets.

## Risks And Mitigations

| Risk | Mitigation in plans |
|------|---------------------|
| Native conversion supports fewer formats than the v1 accepted set. | Make native failure recoverable and immediately try FFmpeg when available. |
| WAV file imports but has wrong bit depth or channel count. | Central `WAVOutputVerifier` blocks output inbox readiness until metadata matches. |
| FFmpeg command paths or URLs are unsafe. | Use `Process` executable URL and `[String]` arguments only; tests assert no shell path. |
| Batch cancellation leaves half-written files marked ready. | Write to `.tmp.wav`, verify before final move, and stop only between files. |
| Output inbox shows unavailable or unverified files as draggable. | Shared drag eligibility helper checks status and file existence. |
| Converter UI grows into a sample editor. | UI-SPEC explicitly excludes waveform editing, trim/fade, analysis, recursion, downloader, and recorder behavior. |

## Open Implementation Details For Executor Judgment

- Whether native AVFoundation covers FLAC on the local target should be proven by tests; fallback behavior is mandatory either way.
- Exact AVAudioConverter buffer size can be chosen during implementation; use a bounded buffer, not full-file loading.
- If 32-bit WAV output is not reliable in v1, keep UI choices to supported bit depths and make acceptance criteria explicit.
- Exact metadata key names are flexible, but `sourceFile`, `sampleRate`, `bitDepth`, `channels`, and `converter` should exist or be intentionally mapped.

## Sources

- Apple Developer Documentation: `AVAudioFile` - sequential read/write with `AVAudioPCMBuffer`: https://developer.apple.com/documentation/avfaudio/avaudiofile
- Apple Developer Documentation: `AVAudioConverter` - PCM and sample-rate conversion: https://developer.apple.com/documentation/avfaudio/avaudioconverter
- Apple Developer Documentation: TN3136 sample-rate conversion guidance: https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions
- Apple Developer Documentation: `AVAudioFormat` - sample rate, channel count, common format, and settings: https://developer.apple.com/documentation/avfaudio/avaudioformat/
- Apple Developer Documentation: Uniform Type Identifiers and SwiftUI drop APIs: https://developer.apple.com/documentation/UniformTypeIdentifiers and https://developer.apple.com/documentation/SwiftUI/View/onDrop%28of%3Adelegate%3A%29-6lin8
- FFmpeg documentation: audio options including `-ac`, `-c:a`, `-sample_fmt`, and option ordering: https://www.ffmpeg.org/ffmpeg.html
- FFprobe documentation: stream inspection and JSON/default output for verification support: https://www.ffmpeg.org/ffprobe-all.html

---
*Research complete for Phase 03 - Cubase-Ready WAV Conversion*
