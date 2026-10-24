# Stem Separation Contract

This document describes the backend boundary used by the v1.7 stem separation feature and how to add a second backend.

## Module

`FeatureStemSeparation` contains the backend contract, the Demucs-MLX adapter, the stem output scanner, and the SwiftUI tool.

## Core types

### `StemSeparationBackend`

```swift
public protocol StemSeparationBackend: Sendable {
    var supportedPresets: [StemSeparationPreset] { get }
    func separate(
        request: StemSeparationBackendRequest,
        onProgress: @escaping @Sendable (Double, String?) -> Void
    ) async -> StemSeparationResult
    func cancel()
}
```

Responsibilities:
- Run separation on one input file and write stems to a folder.
- Publish `(progress, message)` tuples for UI feedback.
- Respond to cancellation.

### `StemSeparationRequest`

Domain request from the UI/service. `destination` is the run's output folder and guard, read once
from settings when the run starts (`ToolOutputDestination.load(from:)` in the view model):

```swift
public struct StemSeparationRequest {
    public let inputURL: URL
    public let destination: ToolOutputDestination
    public let preset: StemSeparationPreset
    public let title: String?
}
```

### `StemSeparationBackendRequest`

The service translates a `StemSeparationRequest` into a backend request with a concrete output folder:

```swift
public struct StemSeparationBackendRequest {
    public let inputURL: URL
    public let outputFolderURL: URL
    public let preset: StemSeparationPreset
}
```

### `StemSeparationResult`

```swift
public enum StemSeparationResult {
    case success(outputFolderURL: URL, stems: [StemFile])
    case failed(message: String)
    case canceled
}
```

## Presets

`StemSeparationPreset` is a domain enum owned by `FeatureStemSeparation`:

```swift
public enum StemSeparationPreset: String, CaseIterable, Sendable, Identifiable {
    case fast4
    case best4
    case experimental6
}
```

Each backend maps presets to its own model identifiers. For `DemucsMLXBackend`:

| Preset | Model |
|--------|-------|
| `fast4` | `htdemucs` |
| `best4` | `htdemucs_ft` |
| `experimental6` | `htdemucs_6s` |

## Output scanning

After the backend returns, `StemSeparationService` runs `StemOutputScanner` over the output folder. The scanner matches filenames against known stem roles (`vocals`, `drums`, `bass`, `other`, `guitar`, `piano`). It rejects files outside the folder and normalizes names to a consistent scheme. Only audio-extension files count as stems, and each must be a regular file that decodes to at least one audio frame; an empty, truncated or non-audio stem fails the job instead of reaching the inbox.

Only stems verified by the scanner are published as `OutputInboxItem` values.

## Job integration

`StemSeparationService.startJob(request:)` enqueues a `Job` via `JobRunning`. The job body calls the backend and then scans/ingests results. UI observes the job through `JobRunning.job(id:)`.

Each run makes a new folder, `Stems/<title> - <preset> - <timestamp> - <uuid>/`, before the backend starts. When the run ends canceled or failed, the service removes that folder and its empty subfolders with `rmdir`, which refuses any folder that holds a file. A stem the backend already wrote keeps its folder.

## Adding a second backend

1. Create a new type conforming to `StemSeparationBackend`.
2. Map `StemSeparationPreset` values to the backend's model/configuration.
3. Implement `separate(request:onProgress:)` and `cancel()`.
4. Keep process spawning shell-safe: build `ExternalProcessRequest` with explicit executable URL and argument arrays.
5. Wire the new backend into `StemSeparationFeature.makeView(context:)` or make it selectable via settings.

No UI or job code should need changes if the contract is respected.

## Helper health

Whether a helper can run is not part of the backend contract. `HelperToolProbe` (AppCore) checks every helper
the same way:

1. Resolve the executable with `HelperToolLocator`: the saved path, then the app's Tools folder, then system folders.
2. Run a light command (`demucs-mlx --list-models`, 30 s).
3. Not found → `.missing`; the command fails or does not answer → `.broken(message:)`; otherwise `.ready(version:)`.

A second backend that needs another helper adds a `HelperTool` case and its command to the probe.

## Command safety

`DemucsMLXCommandBuilder` constructs `ExternalProcessRequest` values with:

- `executableURL` resolved from settings or known paths.
- `arguments` as a `[String]` array.
- No shell command strings.

This prevents shell injection and makes commands inspectable in tests.

## Tests

The module uses fixture-first tests:

- Backend adapters use mocked `ExternalProcessRunning` and captured stdout/stderr fixtures.
- `StemSeparationServiceTests` verify job state, output inbox behavior, source-file safety, and cancellation.
- `StemSeparationViewModelTests` verify SwiftUI view-model state without launching the app.
