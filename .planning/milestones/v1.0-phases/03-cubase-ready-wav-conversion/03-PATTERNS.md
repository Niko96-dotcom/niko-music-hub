# Phase 03 - Pattern Map

**Phase:** 03 - Cubase-Ready WAV Conversion
**Created:** 2026-05-05
**Mode:** Inline GSD pattern mapping

## Purpose

This map connects the planned converter files to existing code so Phase 3 extends the hub instead of creating a parallel app shape.

## Planned Files and Closest Analogs

| Planned file | Role | Closest existing analog | Pattern to copy |
|--------------|------|-------------------------|-----------------|
| `Package.swift` | Add converter target and tests. | Existing `FeatureBPMTapper` target declarations. | Add `FeatureAudioConverter` as a library target, executable dependency, and `FeatureAudioConverterTests`. |
| `Sources/FeatureAudioConverter/AudioConverterFeature.swift` | ToolFeature registration adapter. | `Sources/FeatureBPMTapper/BPMTapperFeature.swift` | Public feature struct with `metadata` and `makeView(context:) -> AnyView`; register in `AppComposition`. |
| `Sources/FeatureAudioConverter/AudioConverterView.swift` | Native SwiftUI converter surface. | `Sources/FeatureBPMTapper/BPMTapperView.swift` and `03-UI-SPEC.md` | Compact top-leading layout, stable intake surface, terse status copy, native controls, bounded content width. |
| `Sources/FeatureAudioConverter/AudioConverterViewModel.swift` | UI state and batch orchestration boundary. | `Sources/FeatureBPMTapper/BPMTapperViewModel.swift` | MainActor observable state with injected use case/services and focused tests. |
| `Sources/FeatureAudioConverter/AudioConversionModels.swift` | Requests, specs, row states, results, supported types. | `Sources/AppCore/Settings/AudioPreset.swift` and `Sources/AppCore/OutputInbox/OutputInboxItem.swift` | Small Codable/Sendable values with explicit defaults and strings used in tests. |
| `Sources/FeatureAudioConverter/NativeAudioConverter.swift` | Native AVFAudio conversion adapter. | `Sources/AppCore/Jobs/JobRunner.swift` for async service style. | Isolated side-effect service, bounded buffers, explicit errors, no UI dependency. |
| `Sources/FeatureAudioConverter/FFmpegAudioConverter.swift` | FFmpeg fallback process adapter. | `Sources/AppCore/Settings/HelperToolSettings.swift` and planned shared process runner. | Build executable URL + argv array, return typed errors, test command construction. |
| `Sources/FeatureAudioConverter/WAVOutputVerifier.swift` | Reusable WAV metadata verification. | `Sources/AppCore/OutputInbox/JSONOutputInboxStore.swift` | File-system side effect wrapped in a focused service with tests. |
| `Sources/FeatureAudioConverter/BatchAudioConversionUseCase.swift` | Native-first/fallback batch flow. | `Sources/AppCore/Jobs/JobRunner.swift` | Progress updates, stop-after-current between files, row-level failures, output inbox writes after verification. |
| `Sources/AppCore/OutputInbox/OutputHandoff.swift` | Shared reveal/drag eligibility. | `Sources/AppCore/OutputInbox/OutputInboxItem.swift` | Testable helper that only allows existing `.available` file URLs. |
| `Sources/OutsideCubaseHub/AppShell/OutputInboxInspectorView.swift` | Output inbox reveal/drag UI. | Existing inspector rows. | Preserve the shared secondary inspector; add drag only for eligible files. |
| `Tests/FeatureAudioConverterTests/*.swift` | Converter feature tests. | `Tests/FeatureBPMTapperTests/*.swift` and `Tests/AppCoreTests/*.swift` | Focused XCTest with fakes for process runner, converter, inbox, settings, and file system. |

## Existing Code Excerpts to Preserve

### Feature Boundary

```swift
public protocol ToolFeature: Sendable {
    var metadata: ToolMetadata { get }

    @MainActor
    func makeView(context: ToolContext) -> AnyView
}
```

The converter should implement this directly and set capabilities to `[.producesFiles, .runsJobs]`.

### Composition Root

```swift
let features: [any ToolFeature] = [
    DevToolFeature(),
    BPMTapperFeature()
]
```

Phase 3 should append `AudioConverterFeature()` here after importing `FeatureAudioConverter`. Do not add converter-specific branching to `AppShellView`.

### Shared Tool Context

```swift
public struct ToolContext: Sendable {
    public let settingsStore: any SettingsStore
    public let outputInboxStore: any OutputInboxStore
    public let jobRunner: any JobRunning
    public let fileActions: any FileActions
    public let diagnostics: any Diagnostics
}
```

The converter should read `settingsStore.loadSettings().audioPreset`, use `outputFolder`, consult `helperTools.ffmpeg`, enqueue long work through `jobRunner`, and write verified outputs through `outputInboxStore`.

### Output Inbox Item

```swift
public struct OutputInboxItem: Identifiable, Equatable, Codable, Sendable {
    public var fileURL: URL
    public var sourceToolID: ToolFeatureID
    public var status: OutputInboxItemStatus
    public var metadata: [String: String]
}
```

Required converter metadata should include source file, sample rate, bit depth, channels, converter, and source type.

## Data Flow

```text
Drop / choose files
    -> AudioConverterViewModel
    -> AudioFileIntakeScanner
    -> BatchAudioConversionUseCase
    -> NativeAudioConverter
    -> FFmpegAudioConverter fallback when needed
    -> WAVOutputVerifier
    -> OutputInboxStore.addItem(.available)
    -> Converter result row + shared output inbox
    -> Reveal in Finder / drag WAV to Cubase
```

## Plan Dependency Notes

| Plan | Dependency reason |
|------|-------------------|
| 03-01 | First because every later slice needs the preset policy, conversion request/result model, native path, verifier, and output naming. |
| 03-02 | Depends on 03-01 because fallback must implement the same converter protocol and produce the same verified WAV contract. |
| 03-03 | Depends on 03-01 and 03-02 because the UI/use case orchestrates native-first plus fallback conversion. |
| 03-04 | Depends on 03-03 because reveal/drag-out needs verified converter results and output inbox items. |

## Anti-Patterns to Avoid

- Do not build FFmpeg commands with `/bin/sh`, `sh -c`, or string interpolation.
- Do not add output inbox items before `WAVOutputVerifier` passes.
- Do not let failed, skipped, pending, or missing rows expose drag-ready behavior.
- Do not recurse into dropped folders in Phase 3.
- Do not put converter-specific branching inside `AppShellView`.
- Do not let `Stop After Current File` interrupt an active conversion and mark a partial file ready.
- Do not broaden Phase 3 into waveform editing, trim/fade, loudness analysis, downloader behavior, or recording.

## Test Pattern Notes

- Use generated short fixtures in temporary directories; never depend on user media files for automated tests.
- Use fakes for process execution and output inbox writes so failure paths are deterministic.
- Use source scans for no-shell and no-unverified-inbox guarantees.
- Keep manual smoke tests for real Finder/Cubase drag behavior.
