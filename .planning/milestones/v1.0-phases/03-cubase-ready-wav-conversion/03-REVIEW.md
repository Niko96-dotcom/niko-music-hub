---
phase: 03-cubase-ready-wav-conversion
reviewed: "2026-05-06T17:10:25Z"
depth: standard
files_reviewed: 35
files_reviewed_list:
  - Package.swift
  - Sources/AppCore/OutputInbox/OutputHandoff.swift
  - Sources/AppCore/Services/ExternalProcessRunning.swift
  - Sources/AppCore/Settings/AudioPreset.swift
  - Sources/FeatureAudioConverter/AudioConversionModels.swift
  - Sources/FeatureAudioConverter/AudioConversionPipeline.swift
  - Sources/FeatureAudioConverter/AudioConverterFeature.swift
  - Sources/FeatureAudioConverter/AudioConverterView.swift
  - Sources/FeatureAudioConverter/AudioConverterViewModel.swift
  - Sources/FeatureAudioConverter/AudioFileIntakeScanner.swift
  - Sources/FeatureAudioConverter/BatchAudioConversionUseCase.swift
  - Sources/FeatureAudioConverter/FFmpegAudioConverter.swift
  - Sources/FeatureAudioConverter/FFmpegHealthChecker.swift
  - Sources/FeatureAudioConverter/FeatureAudioConverter.swift
  - Sources/FeatureAudioConverter/NativeAudioConverter.swift
  - Sources/FeatureAudioConverter/OutputFileNamer.swift
  - Sources/FeatureAudioConverter/WAVOutputVerifier.swift
  - Sources/OutsideCubaseHub/AppComposition.swift
  - Sources/OutsideCubaseHub/AppShell/OutputInboxInspectorView.swift
  - Tests/AppCoreTests/ExternalProcessRunningTests.swift
  - Tests/AppCoreTests/OutputHandoffTests.swift
  - Tests/AppCoreTests/OutputInboxStoreTests.swift
  - Tests/AppCoreTests/SettingsStoreTests.swift
  - Tests/FeatureAudioConverterTests/AudioConversionPipelineTests.swift
  - Tests/FeatureAudioConverterTests/AudioConverterFeatureTests.swift
  - Tests/FeatureAudioConverterTests/AudioConverterHandoffTests.swift
  - Tests/FeatureAudioConverterTests/AudioConverterViewModelTests.swift
  - Tests/FeatureAudioConverterTests/AudioFileIntakeScannerTests.swift
  - Tests/FeatureAudioConverterTests/AudioPresetTests.swift
  - Tests/FeatureAudioConverterTests/BatchAudioConversionUseCaseTests.swift
  - Tests/FeatureAudioConverterTests/FFmpegAudioConverterTests.swift
  - Tests/FeatureAudioConverterTests/FFmpegHealthTests.swift
  - Tests/FeatureAudioConverterTests/NativeAudioConverterTests.swift
  - Tests/FeatureAudioConverterTests/OutputFileNamerTests.swift
  - Tests/FeatureAudioConverterTests/WAVOutputVerifierTests.swift
findings:
  critical: 0
  warning: 3
  info: 0
  total: 3
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-05-06T17:10:25Z
**Depth:** standard
**Files Reviewed:** 35
**Status:** issues_found

## Summary

Reviewed the Phase 03 audio conversion source, app integration, output handoff path, and associated tests after gap-closure commit `d05ffce`. The editable WAV preset work adds a bounded view-model update path, live preset-strip rendering, compact SwiftUI menu controls with a narrow-width fallback, and regression coverage for persistence, queued names, and conversion requests. No new blocker-class defects were found in the gap-closure changes.

`swift build` passed as part of `swift test`. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test` passed with 103 tests and 0 failures.

## Warnings

### WR-01: Output Handoff Treats Any Existing Available WAV As Verified

**Severity:** WARNING
**File:** `Sources/AppCore/OutputInbox/OutputHandoff.swift:32`
**Issue:** `verifiedWAVURL` only checks `status == .available`, a `.wav` extension, and file existence. It does not verify that the current file is still readable WAV PCM or that it matches the Cubase-ready sample rate, bit depth, and channel metadata saved when conversion completed. If an output is corrupted, replaced, or marked available again by `refreshAvailability`, the app can still reveal and drag it as ready.
**Fix:**
```swift
guard item.status == .available,
      item.metadata["verifiedWAV"] == "true",
      let sampleRate = item.metadata["sampleRate"],
      let bitDepth = item.metadata["bitDepth"],
      let channels = item.metadata["channels"] else {
    return nil
}

let expectedSpec = WAVOutputSpec(
    sampleRate: Int(sampleRate) ?? 0,
    bitDepth: Int(bitDepth) ?? 0,
    channelCount: Int(channels) ?? 0
)
guard (try? wavVerifier.verify(url: item.fileURL, expectedSpec: expectedSpec)) != nil else {
    return nil
}
```
Move the verification dependency behind an AppCore-safe service or require a durable verification marker/spec before returning a drag URL.

### WR-02: Output Inbox Does Not Refresh When Conversions Add Files

**Severity:** WARNING
**File:** `Sources/OutsideCubaseHub/AppShell/OutputInboxInspectorView.swift:36`
**Issue:** The inspector loads items only from `onAppear`. `OutputInboxInspectorView` is always present in `AppShellView`, so successful conversions that call `outputInboxStore.addItem` do not update the sidebar until the view is recreated. A completed conversion can leave the Output Inbox saying no outputs are saved.
**Fix:** Make the inbox state observable and refresh it when outputs change, for example by wrapping the store in an `ObservableObject` used by both the converter and inspector, or by posting a typed notification after `addItem` succeeds and handling it in the inspector:
```swift
.onReceive(outputInboxDidChangePublisher) { _ in
    refreshItems()
}
```

### WR-03: Source-Text Tests Give Brittle Coverage For Security And UI Behavior

**Severity:** WARNING
**File:** `Tests/AppCoreTests/ExternalProcessRunningTests.swift:48`
**Issue:** Several tests assert behavior by reading source files and searching for strings, including no-shell checks and UI copy/handoff checks. These can pass while unsafe process construction is reintroduced through another production path, and they can fail on harmless comments or refactors. That weakens regression coverage for the helper-execution boundary this project explicitly treats as security-sensitive.
**Fix:** Replace source-text assertions with behavior tests at the dependency boundary. For process safety, assert that production converters emit an executable URL plus argument array through `ExternalProcessRequest`, and keep shell-capable runners out of the production dependency graph. For UI behavior, exercise the view model/handoff state instead of checking literal source content.

---

_Reviewed: 2026-05-06T17:10:25Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
