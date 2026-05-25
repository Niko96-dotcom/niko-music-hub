# Architecture Research

**Domain:** Native macOS music-production utility hub
**Researched:** 2026-05-04
**Confidence:** HIGH for modular app architecture, MEDIUM for final audio capture adapter details

## Standard Architecture

### System Overview

```text
+--------------------------------------------------------------+
|                         SwiftUI App Shell                    |
|  Sidebar / Toolbar / Settings / Shared Job + Output Views    |
+---------------------------+----------------------------------+
                            |
                            v
+--------------------------------------------------------------+
|                         Feature Registry                     |
|  BPMTapperFeature | ConverterFeature | RecorderFeature | ... |
+---------------------------+----------------------------------+
                            |
                            v
+--------------------------------------------------------------+
|                           Use Cases                          |
|  TapTempo | ConvertAudio | RecordSystemAudio | DownloadURL   |
+---------------------------+----------------------------------+
                            |
                            v
+--------------------------------------------------------------+
|                       Service Ports                          |
| AudioCapturePort | AudioConvertPort | DownloadPort | Files   |
+---------------------------+----------------------------------+
                            |
                            v
+--------------------------------------------------------------+
|                         Adapters                             |
| CoreAudioTap | AVAudioFile | FFmpegProcess | YTDLPProcess    |
+--------------------------------------------------------------+
                            |
                            v
+--------------------------------------------------------------+
|                  Local Files, Output Inbox, Logs             |
+--------------------------------------------------------------+
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| App Shell | Navigation, window, settings, shared output/job surfaces. | SwiftUI views plus AppKit bridges where needed. |
| Feature Registry | Declares available tools and their metadata/view factories. | `ToolFeature` protocol and static registration at app launch. |
| Use Cases | Tool-specific behavior without UI or process details. | Pure Swift types with injected ports. |
| Service Ports | Stable interfaces for side effects. | Protocols for download, conversion, recording, files, logging. |
| Adapters | Concrete implementation of external APIs/tools. | Core Audio, AVFAudio, FFmpeg `Process`, yt-dlp `Process`. |
| Output Inbox | Generated file tracking, reveal, drag-out, preview metadata. | Local JSON/SQLite-lite store plus file-system folder. |
| Job Runner | Background execution with progress/events/cancellation. | Async/await tasks and observable job state. |

## Recommended Project Structure

```text
OutsideCubaseHub/
├── AGENTS.md
├── Package.swift or Xcode project
├── Sources/
│   ├── OutsideCubaseHubApp/
│   │   ├── OutsideCubaseHubApp.swift
│   │   ├── AppShell/
│   │   └── Settings/
│   ├── AppCore/
│   │   ├── Features/
│   │   ├── Jobs/
│   │   ├── Files/
│   │   └── Diagnostics/
│   ├── FeatureBPMTapper/
│   ├── FeatureConverter/
│   ├── FeatureRecorder/
│   ├── FeatureDownloader/
│   └── Infrastructure/
│       ├── Audio/
│       ├── ExternalTools/
│       └── Persistence/
└── Tests/
    ├── AppCoreTests/
    ├── FeatureBPMTapperTests/
    ├── FeatureConverterTests/
    └── InfrastructureTests/
```

### Structure Rationale

- **AppCore:** Shared contracts and primitives stay small and stable.
- **Feature modules:** New tools can be added without touching existing tool internals.
- **Infrastructure:** Side-effect-heavy code is isolated behind ports.
- **Tests by module:** BPM math, command construction, output metadata, and conversion settings can be verified separately.

## Architectural Patterns

### Pattern 1: Feature Module Registration

**What:** Every tool exposes a consistent metadata and view/use-case boundary.
**When to use:** For all tools, even the tiny BPM tapper.
**Trade-offs:** Slight upfront structure, much lower future friction.

```swift
protocol ToolFeature {
    var id: ToolFeatureID { get }
    var title: String { get }
    var capability: ToolCapability { get }
    @MainActor func makeView(context: ToolContext) -> AnyView
}
```

### Pattern 2: Ports and Adapters

**What:** Use cases depend on protocols, not `Process`, Core Audio, or FFmpeg directly.
**When to use:** Anything that touches files, permissions, audio devices, network, or helper tools.
**Trade-offs:** More files, but simpler tests and replacement.

```swift
protocol AudioConverter {
    func convert(_ request: ConversionRequest) async throws -> ConversionResult
}
```

### Pattern 3: Job Runner With Events

**What:** Long-running work reports progress, logs, completion, and cancellation through one shared model.
**When to use:** Downloads, conversion, recording, and batch work.
**Trade-offs:** Needs careful UI-state handling, but prevents each tool inventing its own progress system.

### Pattern 4: Output Inbox as Product Surface

**What:** Generated files are not just saved; they become first-class output items with metadata and actions.
**When to use:** Every file-producing feature.
**Trade-offs:** Requires a small persistence layer, but makes drag/drop into Cubase pleasant.

## Data Flow

### BPM Tapper Flow

```text
User tap/click/space
    -> BPMTapperViewModel
    -> TapTempoUseCase
    -> TempoEstimator
    -> BPM result + history item
```

### Conversion Flow

```text
Dropped audio files
    -> ConvertAudioUseCase
    -> AudioConverter port
    -> AVAudio adapter or FFmpeg adapter
    -> WAV file
    -> Output Inbox
```

### Recording Flow

```text
Record button
    -> Permission check
    -> RecordSystemAudioUseCase
    -> CoreAudioTap adapter
    -> WAV writer
    -> Output Inbox
```

### Download Flow

```text
URL input
    -> Validate/normalize URL
    -> DownloadURLUseCase
    -> YTDLPProcess adapter
    -> Progress events
    -> Output Inbox
```

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Personal local use | File-based output metadata and in-process jobs are enough. |
| Many batch jobs | Add job persistence and queue recovery after app restart. |
| Public distribution | Add signed helper management, update checks, notarization, and license review. |

### Scaling Priorities

1. **First bottleneck:** Long-running jobs blocking the UI. Use async job runner from the start.
2. **Second bottleneck:** Feature coupling. Keep feature modules honest before adding more tools.
3. **Third bottleneck:** Helper tool drift. Add explicit health checks and version display.

## Anti-Patterns

### Anti-Pattern 1: UI Owns External Tool Commands

**What people do:** Build command arrays directly in SwiftUI views.
**Why it's wrong:** Hard to test, insecure, and brittle when options grow.
**Do this instead:** Use downloader/converter use cases and process adapters.

### Anti-Pattern 2: Recording Polish Before Capture Proof

**What people do:** Design a beautiful recorder UI before proving system audio capture works.
**Why it's wrong:** The riskiest part is permission/API behavior, not buttons.
**Do this instead:** Build a minimal capture-to-WAV path early.

### Anti-Pattern 3: "Temporary" Hard-Coded Tool List

**What people do:** Hard-code BPM/converter/downloader views in the sidebar.
**Why it's wrong:** It trains the codebase against the user's explicit extensibility goal.
**Do this instead:** Register tools through `ToolFeature`.

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| yt-dlp | `Process` adapter with explicit args and parsed progress output. | Avoid shell interpolation; show version and update guidance. |
| FFmpeg | `Process` adapter for fallback conversion and metadata probing. | Parse failures into user-facing errors. |
| Core Audio | Native adapter behind `AudioCapturePort`. | Requires permission flow and early proof. |
| Finder | AppKit/NSWorkspace integration. | Reveal output, drag file URLs, open output folder. |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Feature -> Use Case | Direct dependency injection | Feature owns UI, use case owns behavior. |
| Use Case -> Adapter | Protocol | Tests use fakes. |
| Job Runner -> UI | Observable job events | One progress/error model across tools. |
| Output Inbox -> Features | Shared service | File-producing features append output items. |

## Sources

- https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps - Audio capture adapter boundary.
- https://developer.apple.com/documentation/avfaudio/avaudiofile - WAV/native audio file implementation context.
- https://github.com/yt-dlp/yt-dlp/blob/master/README.md - Downloader helper integration context.
- https://ffmpeg.org/ffmpeg.html - FFmpeg process adapter behavior.

---
*Architecture research for: Native macOS music-production utility hub*
*Researched: 2026-05-04*
