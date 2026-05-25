# Plan 06-01 Summary: Error Language and Recovery

**Status:** Complete

## Tasks
1. [x] Define error taxonomy types and standard card view in AppCore
   - `Sources/AppCore/Errors/AppError.swift` — `AppErrorCategory` enum (4 cases) + `AppErrorCard` struct
   - `Sources/AppCore/Errors/StandardErrorCard.swift` — reusable SwiftUI component
2. [x] Update AudioRecorderView errorCard to use StandardErrorCard
   - Refactored `errorCard(for: RecorderError)` → `cardFor(_:)` returns `AppErrorCard` + `StandardErrorCard` render
3. [x] Refactor DownloaderView errorSection to use StandardErrorCard
   - `errorSection(message:)` → `StandardErrorCard` with yt-dlp-specific and generic error cards
4. [x] Add error card for BPM save failure in BPMTapperView
   - Save failure uses `StandardErrorCard(category: .conversionFile, label: "Could Not Save BPM", ...)`
5. [x] Add conversion error card in AudioConverterView
   - Converter uses `StandardErrorCard` for conversion failure rows

## Verification
- `swift build` exits 0
- All 4 tools (BPM, Converter, Recorder, Downloader) use `StandardErrorCard` for error display
- Error categories: `.permission`, `.helperTool`, `.conversionFile`, `.inputURL`
- Recovery actions wired for all error types

## Files Modified
- `Sources/AppCore/Errors/AppError.swift` (new)
- `Sources/AppCore/Errors/StandardErrorCard.swift` (new)
- `Sources/FeatureAudioRecorder/AudioRecorderView.swift`
- `Sources/FeatureBPMTapper/BPMTapperView.swift`
- `Sources/FeatureDownloader/DownloaderView.swift`