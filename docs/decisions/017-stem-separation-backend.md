# Decision: First stem-separation backend for v1.7

**Status:** Accepted  
**Date:** 2026-06-13  
**Deciders:** Niko Music Hub product/implementation  
**Scope:** v1.7 Local Stem Separation

## Context

The v1.7 milestone adds local multi-stem separation to Niko Music Hub. The app must remain a native SwiftUI macOS product; it must not embed alternate-language runtimes, full GUI applications, or model-lab UIs. We need a backend that:

- Runs locally on Apple Silicon Macs.
- Supports the core Demucs four-stem workflow (vocals, drums, bass, other).
- Optionally supports six-stem output (guitar, piano) without overpromising quality.
- Is MIT- or similarly licensed so it can be linked/invoked from a native app.
- Has current maintenance and a plausible install path for production users.

## Candidates considered

| Candidate | Verdict | Rationale |
|-----------|---------|-----------|
| **demucs-mlx** | **First backend** | Apple Silicon–native, MLX/Metal, no PyTorch at inference, supports `htdemucs`, `htdemucs_ft`, and `htdemucs_6s`, MIT license, actively maintained by `ssmall256`, matches the requested four-stem + optional six-stem workflow. |
| **mlx-audio-separator** | Model-zoo follow-up | Built on the same author’s MLX work, supports UVR/MDX/MDXC/VR/Roformer model zoo. Promising, but exposes too many knobs for a first curated workflow. Deferred until the backend contract is proven. |
| **StemDeck** | Defer / reference only | Nice UX reference for local six-stem expectations, but it is a separate GUI/Electron-style product. Embedding it would violate the native-app boundary and bloat the product. |
| **Audio Separator (`audio-separator` Python package)** | Defer | Cross-platform Python package with broad model support, but it is PyTorch-based and exposes a model zoo too early. Watchlisted for future backend evaluation. |
| **UVR5 (Ultimate Vocal Remover GUI)** | Defer | Valuable model-lab reference, but it is a standalone Python GUI with heavy dependencies. Not embeddable in a native Swift product. |
| **demucs.cpp** | Defer / watchlist | C++ port of Demucs attractive for a Python-free future, but it is experimental and lacks the breadth and current maintenance of `demucs-mlx`. |
| **demucs-rs** | Defer / watchlist | Rust port; interesting for eventual native integration, but immature and not a safe first backend. |

## Decision

Use **`demucs-mlx`** as the first supported stem-separation backend.

- Curated presets map to Demucs model identifiers:
  - Fast 4-stem → `htdemucs`
  - Best 4-stem → `htdemucs_ft`
  - Experimental 6-stem → `htdemucs_6s`
- The adapter lives in a new `FeatureStemSeparation` Swift module.
- The adapter builds `ExternalProcessRequest` values with an explicit executable URL and argument arrays; no shell command strings.
- Model cache and runtime health are checked before the UI allows a run.
- No Python source or third-party ML project code is stored inside Swift product modules.

## Consequences

- Users must install `demucs-mlx` separately (e.g., via `pip install demucs-mlx` or a future installer).
- First-run model download/conversion time is surfaced honestly in the UI.
- The backend contract (`StemSeparationBackend`, `StemBackendHealth`) is designed so a second backend (`mlx-audio-separator`, a future Swift MLX port, etc.) can be added without rewriting job or UI code.
- CI remains deterministic because all production-code tests use mocked process runners.

## References

- `docs/reference/cubase-file-orga/` (archive/output conventions)
- `Sources/FeatureDownloader/YtDlpHealthChecker.swift` (health-check pattern)
- `Sources/FeatureAudioConverter/FFmpegHealthChecker.swift` (health-check pattern)
- `Sources/AppCore/Services/ExternalProcessRunning.swift` (process-running contract)
