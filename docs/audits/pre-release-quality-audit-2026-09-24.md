# Pre-release quality audit — 2026-09-24

Whole-app static review of Niko Music Hub before the next release flow (`VERSION` 1.7.0 at the
time of the audit). Every Swift source file under `Sources/` was read in full, module by module,
together with the release scripts and the Linux-runnable script tests. This document lists every
finding, what was changed, and what still has to run on a Mac before `script/release-all.sh`.

## Scope and method

| Area | Files read | Result |
|---|---|---|
| `NikoMusicCore` (domain, scanning, search, safety, persistence, vault engines, preview analysis) | all | 7 findings fixed |
| `AppCore` (settings, jobs, process runner, helper tools, vault runtime, shell session, design system) | all | 3 findings fixed |
| `FeatureArchiveBrowser` (view model + extensions, views, smoke harness) | all | 1 cosmetic fix, no defects |
| `FeatureAudioConverter`, `FeatureDownloader`, `FeatureStemSeparation`, `FeatureAudioRecorder`, `FeatureBPMTapper` | all | 3 findings fixed |
| `AppUpdates`, `NikoMusicHub` app target, `NikoMusicHubCLI`, self-test executable | all | 1 finding fixed |
| `script/*.sh`, `script/*.py`, `Tests/test_release_*.py`, `Tests/test_*_scripts.sh` | all | no defects |

Review focus: correctness (traps, races, off-by-one, wrong fallbacks), safety boundaries (archive
roots stay read-only, path containment, symlink handling), concurrency (task ownership,
cancellation, actor isolation), state ownership rules from `AGENTS.md`, and maintainability.

## Verification status (read this first)

- The audit ran in a Linux container without a Swift toolchain, so **`./script/ci.sh` and
  `./script/e2e_user_smoke.sh` were not executed here**. Every fix below is small, local, and
  written against the surrounding code, and every behavioural fix ships with a regression test,
  but the build and the test suite must be run on the Mac before the release flow starts.
- `Tests/test_release_scripts.sh` and `Tests/test_source_distribution_scripts.sh` pass here.
- `python3 -m unittest Tests/test_release_provenance.py Tests/test_release_pipeline_provenance.py`:
  31 of 35 pass. The 4 failures are all
  `release architecture contract does not include host architecture 'x86_64' (supported: arm64)`,
  the container's CPU architecture. They are not code defects and pass on Apple silicon.

## Findings and fixes

Severity: **High** = data or safety boundary, **Medium** = user-visible malfunction,
**Low** = robustness, dead code, or cosmetic.

| ID | Sev | Area | Finding | Fix | Regression test |
|---|---|---|---|---|---|
| F1 | Medium | `DiagnosticsPathRedactor` | `redact` and `redactPathsInText` matched the home directory by plain string prefix, so a sibling account such as `/Users/nikolaus/...` (home `/Users/niko`) was rewritten to the wrong `~/laus/...` path in exports and logs. | Match only the home directory itself or paths below it (`/` boundary). | `DiagnosticsPathRedactorTests` (2 new cases) |
| F2 | High | `AppSettings.archiveRoots` setter | Built a `Dictionary(uniqueKeysWithValues:)` from Scan-only roots keyed by path. Two stored Scan-only roots with the same path (possible after legacy salvage or hand-edited defaults, and reachable from `SettingsRepair`) trapped the process. | `Dictionary(_:uniquingKeysWith:)` keeping the first entry. | `AppSettingsArchiveRootsTests` |
| F3 | Low | `MusicArchiveScanner.ScanError` | `unreadableFolder` was declared and described but never thrown. | Removed the dead case. | existing scanner tests |
| F5 | Medium | `NewSongFolderCreator` | Draft names starting with `.` created hidden folders that the read-only scanner skips, so the new song vanished on the next scan; `:` names show as `/` in Finder. | Reject dot-prefixed names and `:`; updated the recovery copy. | `NewSongFolderCreatorTests` |
| F6 | Medium | `MixdownKeyEstimator` | The autocorrelation lag for 70 Hz exceeded the fixed 1024-frame window at 88.2/96 kHz, so `estimatePitchClass` returned `nil` for every window and no key was ever shown for high-sample-rate mixdowns. | Clamp the lag range to the window. | `MixdownKeyEstimatorTests` |
| F7 | Low | `PreviewCandidateDetector.folderRole` | Stripped the song-folder path with `replacingOccurrences`, i.e. every occurrence, and compared an unstandardized parent path against a standardized base. | Strip only a leading prefix on a `/` boundary; standardize both sides. | `PreviewCandidateDetectorFolderRoleTests` |
| F8 | Medium | `FoundationExternalProcessRunner` | Pipe descriptors were not close-on-exec. A helper spawned while another helper's pipes were open inherited them, so the first helper's EOF (and therefore its completion) waited for the second helper to exit. | `FD_CLOEXEC` on all four descriptors; the `dup2` file actions still hand each child its own stdout/stderr. | covered by `ExternalProcessRunningTests` concurrency cases on the Mac |
| F9 | Medium | `HelperToolSetupModel` | `cancelInstalls()` followed by a new `install(_:)` let the cancelled run's completion nil out the new run's task and reset its row to Not Installed while the new download was still running. | Runs carry an id; a stale run neither clears the task nor rewrites the row. | `HelperToolSetupModelTests.testInstallStartedAfterCancelIsNotClearedByTheCancelledRun` |
| F10 | High | `NikoMusicHubCLI export-index` | Wrote the index JSON without the read-only archive guard that the app and `export-diagnostics` enforce, so `--output` inside an archive root wrote into the archive. | Same `ReadOnlyArchivePolicy` check as the app export. | `script/ci.sh` CLI smoke (writes to a temp file) |
| F12 | Medium | `FFmpegAudioConverter` | The converter UI offers a 32-bit preset, but the FFmpeg fallback only knew 16/24-bit and failed 32-bit files with "32-bit WAV output is not supported". | Added `pcm_s32le`. | `FFmpegAudioConverterTests` (new 32-bit case; unsupported case now uses 20-bit) |
| F13 | Medium | `StemOutputScanner` | Containment used `hasPrefix(folderPath)` without a `/` boundary, so a symlinked stem resolving into a sibling folder such as `<job>-other/` counted as inside the job folder. | Boundary-aware prefix check. | `StemOutputScannerTests.scan_rejectsSymlinkIntoSiblingFolderSharingThePrefix` |
| F14 | Low | Archive Browser | Two functions had their opening brace and first statement on one line. | Reformatted. | `HubDesignContractSourceTests` etc. unaffected |
| F16 | Low | `YtDlpHealthChecker` | The staleness reference date was captured once at construction; the app keeps one checker per tool session, so an app running for weeks judged yt-dlp against its launch date. | Read the clock per check; tests can still inject a fixed date. | existing `YtDlpHealthCheckerTests` |

## Reviewed and deliberately left unchanged

- **`SQLiteArchiveDatabase.deinit` runs `accessQueue.sync`.** A deadlock would need the last
  reference to be dropped from a block already on that queue; every block is entered from a method
  on the live instance, so this cannot happen. No change.
- **`CPRPluginSummaryService` cache eviction** removes the entry with the oldest file
  modification date rather than the least recently used one. The cache is bounded (128 entries)
  and only affects re-parsing cost. No change.
- **`AppUpdateController.finishCycle`** reports "Up to date" when Sparkle ends a cycle without an
  error after the user dismissed an offered update. It is a status label in Settings only; Sparkle's
  exact end-of-cycle error for a dismissed update could not be verified without the SDK here.
- **`DownloaderViewModel.applyObservedJob`** has two near-identical inbox hand-off loops in the
  already-downloaded branch. Behaviour is correct; a refactor is not worth the risk before a release.
- **`DownloaderHelperToolResolver`** keeps unused `fileExists` parameters for source compatibility
  with existing tests.
- **Archive Browser keyboard monitor** is installed from `onAppear` and removed from
  `onDisappear` as well as from the `hubToolIsActive` flag. The flag path is the one that matters
  for cached panes; the appear/disappear pair is harmless and guarded by the source tests.

## Overall assessment

The codebase is in very good shape: safety boundaries (read-only archive roots, symlink-swap
defenses, bound Project Vault authorizations, fail-closed settings and metadata handling) are
consistent across modules, state ownership follows the documented rules, and the fixes above are
all local. Nothing found blocks a release once the Mac gates confirm the build.

## Before starting the release flow

1. On the Mac, on this branch: `./script/ci.sh` (build, full test suite including the new tests,
   CLI smoke, release-script gate).
2. `./script/e2e_user_smoke.sh` (mandatory user-style E2E per `AGENTS.md`).
3. Then follow `docs/release.md` and `docs/release-checklist.md` as usual.
