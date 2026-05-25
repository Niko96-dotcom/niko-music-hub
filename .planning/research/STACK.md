# Stack Research

**Domain:** Native macOS music-production utility hub
**Researched:** 2026-05-04
**Confidence:** HIGH for native macOS stack, MEDIUM for final helper-tool packaging

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Swift | 6.3 locally installed | App, domain logic, adapters, tests | Best fit for native macOS APIs, file handling, permissions, and long-lived maintainability. |
| SwiftUI | macOS 14.2+ target, current SDK during implementation | Main UI shell and tool surfaces | Good for a focused desktop utility with sidebar navigation, settings, drag/drop, and progress views. |
| AppKit interop | macOS native | Finder reveal, file panels, drag-out behavior, window/menu details | SwiftUI alone may be thin for polished macOS file workflows. |
| Core Audio process taps | macOS 14.2+ | Internal/system audio capture | Apple's audio-only route for capturing outgoing audio from processes or groups of processes. |
| AVFAudio / AVFoundation | Current Apple frameworks | Audio file reading/writing and native conversion | `AVAudioFile` reads/writes through `AVAudioPCMBuffer`, which fits WAV export and testable conversion paths. |
| FFmpeg | 8.1 locally installed | Broad conversion fallback and media post-processing | Covers formats and edge cases native frameworks may not handle. Keep behind an adapter. |
| yt-dlp | 2026.03.17 locally installed | Website media/file download backend | Mature downloader for thousands of supported sites; integrate as an external tool, not UI logic. |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| UniformTypeIdentifiers | macOS framework | File type filtering for WAV, M4A, MP3, AIFF, URLs | Drag/drop, import panels, and output validation. |
| OSLog | macOS framework | Structured diagnostics | Long-running jobs, helper tool failures, permission problems. |
| XCTest | Swift toolchain | Unit/integration tests | BPM calculations, command construction, conversion outputs, feature registration. |
| ScreenCaptureKit | macOS 12.3+ / current | Possible fallback or comparison path for system audio capture | Use only if Core Audio taps do not satisfy the exact capture workflow. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Swift Package Manager | Package boundaries and tests | Use separate targets for core, features, and adapters where helpful. |
| Homebrew FFmpeg and yt-dlp | Development-time helper tools | Local machine already has both; app should still detect missing tools. |
| Git / GSD planning docs | Roadmap and context continuity | Planning files are committed for traceability. |

## Installation

```bash
# Development helper tools already present locally, but these are the expected install commands.
brew install ffmpeg yt-dlp

# Swift is provided by Xcode / command line tools.
swift --version
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| SwiftUI + AppKit interop | Electron | Use Electron only if the app becomes cross-platform and gives up on deep native audio integration. |
| Core Audio process taps | BlackHole/Soundflower-style loopback device | Use a virtual audio device only if Apple's capture APIs fail for the target workflow. |
| Native AVFAudio first | FFmpeg-only conversion | Use FFmpeg-only if native conversion cannot consistently produce desired WAV specs. |
| yt-dlp CLI adapter | Embedding yt-dlp as a Python library | Embed only if command-line process control becomes too limiting. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| One huge SwiftUI view model | Makes future tools painful to add and test. | Feature registry plus separate use cases/services. |
| Shell string command construction | URL/file paths can break or become unsafe. | `Process` with explicit executable URL and argument array. |
| Unreviewed bundling of FFmpeg/yt-dlp binaries | Licensing, updates, and notarization need deliberate handling. | Development-time external tools first; packaging decision later. |
| Full DAW feature creep | Duplicates Cubase and delays the useful companion workflow. | Small utilities that hand files back to Cubase. |

## Stack Patterns by Variant

**If the first milestone is for personal local use only:**
- Use externally installed `ffmpeg` and `yt-dlp` with visible health checks.
- Because it avoids packaging/licensing friction while validating the workflow.

**If the app is packaged for others later:**
- Add a Tool Manager that downloads/verifies helpers or documents required installs.
- Because downloader/converter helper ownership affects licensing, updates, signing, and support.

**If macOS 14.2+ is acceptable:**
- Use Core Audio taps for internal audio capture.
- Because the user wants audio, not screen recording.

**If older macOS support becomes mandatory:**
- Re-evaluate ScreenCaptureKit and virtual audio device fallback options.
- Because Core Audio process taps require macOS 14.2+.

## Version Compatibility

| Package A | Compatible With | Notes |
|-----------|-----------------|-------|
| Core Audio process taps | macOS 14.2+ | Requires `NSAudioCaptureUsageDescription` and system audio recording permission. |
| yt-dlp standalone macOS executable | macOS 10.15+ per project README | Current README lists `yt-dlp_macos` as the recommended macOS standalone executable. |
| yt-dlp Python install | Python 3.10+ CPython | README lists Python 3.10+ support for current versions. |
| yt-dlp post-processing | FFmpeg and ffprobe highly recommended | Required for many merge/post-processing tasks. |
| AVAudioFile | macOS AVFAudio | Reads/writes sequentially using `AVAudioPCMBuffer`. |

## Sources

- https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps - Core Audio process tap approach and macOS 14.2+ requirement.
- https://developer.apple.com/documentation/ScreenCaptureKit/capturing-screen-content-in-macos - ScreenCaptureKit audio capture behavior and fallback context.
- https://developer.apple.com/documentation/avfaudio/avaudiofile - Native audio file read/write model.
- https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox - Sandboxed file access constraints.
- https://github.com/yt-dlp/yt-dlp/blob/master/README.md - yt-dlp install, release files, dependencies, and update behavior.
- https://ffmpeg.org/ffmpeg.html - FFmpeg conversion/post-processing command behavior.

---
*Stack research for: Native macOS music-production utility hub*
*Researched: 2026-05-04*
