# Quick Task 260523-2ec: fix Testing - Context

**Gathered:** 2026-05-22
**Status:** Ready for planning

<domain>
## Task Boundary

Restore a green `swift test` run: fix broken test migration, Package.swift test targets, and environment-sensitive integration tests.

</domain>

<decisions>
## Implementation Decisions

### Test framework
- Revert incomplete Swift Testing migration; keep XCTest (works with Xcode toolchain).

### Package targets
- Register all feature test targets including `FeatureAudioConverterTests` and `FeatureDownloaderTests`.
- Add `FeatureAudioConverter` to `FeatureAudioRecorderTests` dependencies.

### Toolchain
- XCTest requires full Xcode (`DEVELOPER_DIR`); add `scripts/test.sh` wrapper.

### Integration tests
- Skip Core Audio tap tests when system audio permission is not granted.
- Fix contradictory permission tests and yt-dlp health tests for auto-detect behavior.

### Claude's Discretion
- Expose `parseProgressPercentage` as internal for `@testable` downloader tests.

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<canonical_refs>
## Canonical References

No external specs — requirements fully captured in decisions above

</canonical_refs>
