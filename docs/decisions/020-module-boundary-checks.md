# Decision: Enforce the module rules in the local gates

**Status:** Accepted — implemented (strict import check in `ci.sh` and the app-bundle build, `ModuleBoundarySourceTests`)  
**Date:** 2026-09-27  
**Deciders:** Niko Music Hub owner + implementation  
**Scope:** `script/ci.sh`, `script/lib/app_lifecycle.sh`, `Tests/AppCoreTests/ModuleBoundarySourceTests.swift`

## Context

The module rules — `NikoMusicCore` has no SwiftUI/AppKit, feature modules stay
independent except Stem Separation → Downloader — held, but only review kept
them so. The one boundary test, `HubDependencyDirectionTests`, covers
`AppCore/Components`, not modules.

A plain `swift build` does not reject an undeclared target import reliably. A
planted `import FeatureDownloader` in `FeatureBPMTapper` failed a clean build
only because of build order ("no such module"); once `FeatureDownloader` had
been built, the same file compiled with exit 0.
`swift build --explicit-target-dependency-import-check error` rejects it
("imports another target … without declaring it a dependency") and passes on the
real tree, test targets included.

## Decision

1. The product builds pass `--explicit-target-dependency-import-check error`:
   `script/ci.sh` (with the test targets) and `nmh_build_bundle` in
   `script/lib/app_lifecycle.sh` (dev bundle, E2E smoke, local install and the
   release bundle). `dev.sh check` runs `ci.sh`, so it follows. `Tests/test_release_scripts.sh` pins the bundle build
   line with the flag.
2. `ModuleBoundarySourceTests.testNikoMusicCoreImportsOnlyAllowedFrameworks`
   pins Core's imports to Foundation, Darwin, SQLite3, AVFoundation, CryptoKit
   and zlib.
3. `ModuleBoundarySourceTests.testFeatureModulesImportOnlyDocumentedFeatureEdges`
   pins feature→feature imports to exactly FeatureStemSeparation →
   FeatureDownloader. The strict flag catches an import without a
   `Package.swift` edge; this test catches a new edge that was declared but not
   documented. Adding an edge means changing `docs/architecture.md` and this
   test in the same commit, like the design contract.
4. `ModuleBoundarySourceTests.testProductBuildsUseStrictTargetImportCheck`
   fails if any command in those two scripts that runs `swift build` (or
   `nmh_swift build`) drops the flag, after stripping shell comments and
   splitting `;`, `&&` and `||` chains. `--show-bin-path` only prints a path and
   is exempt.

## Options

| Option | Complexity | Pros | Cons |
|---|---|---|---|
| A. Strict flag only | Low | A few script lines; catches undeclared imports | A new `Package.swift` edge still passes silently |
| **B. Flag + allowlist tests** | Low | Also catches a deliberate but undocumented edge, and UI creeping into Core | Two more source tests to keep |
| C. Split into several packages | High | Hard boundaries | Large `Package.swift` churn for no current defect |

## Consequences

- Boundary regressions fail locally with a clear message in `ci.sh`, the dev
  bundle and E2E.
- The flag adds no measurable time to an incremental build.
- `ci.sh`'s strict build includes the test targets (`--build-tests`), so a
  test target's undeclared import fails the gate too. `swift test` then reuses
  that build.
- `script/ci-release.sh` builds with the same flag, and
  `ModuleBoundarySourceTests` pins it there too.
- The benchmark scripts build single targets for timing and stay as they are.

## Open

- Pinning the `@unchecked Sendable` count per module (optional) is not done.
- The import scan is line-based: an import written after a block comment on the
  same line (`/* x */ import SwiftUI`) is not seen, and an `import` line inside
  a block comment or multi-line string would fail it falsely. Neither exists
  today; strip comments and strings first if either shows up.
- The documented edge list lives in the test constant; the test does not parse
  `docs/architecture.md`, so the two are kept in step by review.
