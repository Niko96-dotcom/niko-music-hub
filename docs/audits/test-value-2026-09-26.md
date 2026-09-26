# Test value audit — 2026-09-26

Baseline: `55facd6eea6d5afbaa52775de710b1a8ea7d9df0`.

The requested target was approximately 20% fewer tests with production coverage
within two percentage points. This pass removes **46 of 2,387 discovered tests
(1.93%)**, leaving **2,341**. **The 20% target was not reached:** the reviewed
candidates did not justify deleting another 432 tests. Distinct edge cases,
defaults, integration wiring, safety and binding design guards were retained.
There was no mass parameterization or weakening of assertions to reduce the count.

The method follows [OpenClaw's test audit](https://github.com/openclaw/openclaw/blob/main/.agents/skills/test-audit/SKILL.md):
record baseline, inspect each proposed deletion and its owner, identify remaining
proof, then check the changed suite. Local Swift/CI/E2E gates replace OpenClaw's
repository-specific Vitest/crabbox/PR commands. This is a focused value audit,
not a completed per-declaration audit of the entire repository. Discovery covered
shell/quick access, diagnostics/search/preview, feature tools and a sweep of
shared services and short archive suites. High-risk Vault/storage/security
suites and the larger archive workflows were retained without attempting a quota.

## Before and after

| Measurement | Baseline | Candidate | Change |
|---|---:|---:|---:|
| Discovered Swift tests (XCTest + Swift Testing) | 2,387 | 2,341 | -46 (-1.93%) |
| Production line coverage | 40,071 / 61,448 (65.2112%) | 40,057 / 61,448 (65.1885%) | -0.0228 percentage points |
| Production function coverage | 5,014 / 7,352 (68.1991%) | 5,010 / 7,352 (68.1447%) | -0.0544 percentage points |
| Production region coverage | 14,359 / 20,947 (68.5492%) | 14,356 / 20,947 (68.5349%) | -0.0143 percentage points |
| XCTest run, with existing hardware exclusions | 2,314; 8 skipped; 0 failures | 2,269; 8 skipped; 0 failures | -45 |
| Swift Testing run | 67 passed | 66 passed | -1 |
| Test/support LOC | 77,503 | 76,892 | -611 |
| Production/tooling LOC changed | 0 | 0 | 0 |

Coverage uses `swift test --enable-code-coverage` and LLVM exports. The denominator
is the **same 387 production files in the nine test-instrumented modules**, with
identical executable line/function/region counts. Test code, dependencies and
generated build files are excluded. The app/CLI executable targets are outside
this unit-test coverage denominator; E2E is separate evidence. All production,
package and script files remain byte-identical. AppCore loses 14 covered lines
net (15 font-token lines lost, one process-runner line gained); every other
module's covered-line count is unchanged. Line coverage is a guardrail, not proof
that a removed assertion was redundant.

## Deletion ledger

All paths below are under `Tests/`. Exact declaration names precede the keeper.
No production seam was deleted. Two duplicate-only files and one test-only
`ContextAwareFeature` fixture were removed.

### `AppCoreTests/HubDesignSystemTokenTests.swift`

- `testTypographySurfaceIncludesExpandedScale`: Calls font factories and discards every result; API availability is already required by shipping views. Keeper: Application/component-preview call sites compile these APIs; body-scaling and ten-point-floor guards remain, without claiming to assert every font factory.

### `AppCoreTests/HubSurfaceTests.swift`

- `testHubSurfaceAppliesToAllLevelsAndStates`: Constructs and discards view modifiers without mounting or inspecting them. Keeper: Hosted card-state coverage, radii and binding material/focus guards remain. These do not cover every surface level, and the deleted test did not render those levels either.

### `AppCoreTests/AppCoreSmokeTests.swift`

- `testRegistryExposesFeatureMetadataInOrder`: Repeats the same two-feature label ordering assertion. Keeper: FeatureRegistryTests.testPreservesRegistrationOrder asserts the same labels and their IDs.

### `AppCoreTests/QuickAccessCommandTests.swift`

- `testOpenToolCarriesToolFeatureID`: Constructs an enum case then pattern-matches that same local value; no routing behavior is exercised. Keeper: QuickAccessRouterTests exercises actual command effects; allowlist command mapping assertions remain.
- `testOpenAppHasNoAssociatedValue`: Constructs an enum case then pattern-matches that same local value; no routing behavior is exercised. Keeper: QuickAccessRouterTests exercises actual command effects; allowlist command mapping assertions remain.
- `testQuitAppHasNoAssociatedValue`: Constructs an enum case then pattern-matches that same local value; no routing behavior is exercised. Keeper: QuickAccessRouterTests exercises actual command effects; allowlist command mapping assertions remain.
- `testRevealOutputInboxHasNoAssociatedValue`: Constructs an enum case then pattern-matches that same local value; no routing behavior is exercised. Keeper: QuickAccessRouterTests exercises actual command effects; allowlist command mapping assertions remain.
- `testAllowlistHasSevenEntries`: Count, absence and uniqueness are strict subsets of the retained exact ordered seven-ID array assertion. Keeper: QuickAccessCommandTests.testAllowlistOrderMatchesSpec.
- `testAllowlistOmitsSettings`: Count, absence and uniqueness are strict subsets of the retained exact ordered seven-ID array assertion. Keeper: QuickAccessCommandTests.testAllowlistOrderMatchesSpec.
- `testAllEntryIDsAreUnique`: Count, absence and uniqueness are strict subsets of the retained exact ordered seven-ID array assertion. Keeper: QuickAccessCommandTests.testAllowlistOrderMatchesSpec.

### `AppCoreTests/QuickAccessAllowlistTests.swift`

- `testResolvedOrderMatchesAllowlistOrder`: Weaker subsequence assertion for the identical complete registry. Keeper: testFullRegistryReturnsAllSevenEntries compares the exact ordered IDs for makeFullRegistry().

### `AppCoreTests/QuickAccessRouterTests.swift`

- `testRouterSourceDoesNotReferenceOutputHandoff`: Exact duplicate source-file and substring guard. Keeper: QuickAccessSourceTests.testQuickAccessRouterDoesNotReferenceOutputHandoff.

### `AppCoreTests/ToolContextTests.swift`

- `testContextCanBePassedToFeatureViewFactory`: Only assertion is the ID hardcoded by ContextAwareFeature in this same test file; generated view is discarded. Keeper: testContextInjectsSharedServices retains service injection; actual feature integration tests remain.

### `AppCoreTests/QuickAccessRoutingSmokeTests.swift`

- `testWAVConverterResolvesInStubRegistry`: Repeats menu/router owner tests and the executable quick-access E2E checks. Keeper: MenuBarMenuModelTests.testWAVConverterRowMapsCorrectly/testEmptyRegistryYieldsOnlyOutputInbox; QuickAccessRouterTests.testExecuteOpenToolPublishesNewRequest/testExecuteRevealOutputInboxSetsFlag; e2e quick_access_selected_tool and reveal markers check both final values.
- `testOutputInboxAlwaysResolvesWithEmptyRegistry`: Repeats menu/router owner tests and the executable quick-access E2E checks. Keeper: MenuBarMenuModelTests.testWAVConverterRowMapsCorrectly/testEmptyRegistryYieldsOnlyOutputInbox; QuickAccessRouterTests.testExecuteOpenToolPublishesNewRequest/testExecuteRevealOutputInboxSetsFlag; e2e quick_access_selected_tool and reveal markers check both final values.
- `testOpenToolPublishesRequest`: Repeats menu/router owner tests and the executable quick-access E2E checks. Keeper: MenuBarMenuModelTests.testWAVConverterRowMapsCorrectly/testEmptyRegistryYieldsOnlyOutputInbox; QuickAccessRouterTests.testExecuteOpenToolPublishesNewRequest/testExecuteRevealOutputInboxSetsFlag; e2e quick_access_selected_tool and reveal markers check both final values.
- `testRevealOutputInboxSetsFlag`: Repeats menu/router owner tests and the executable quick-access E2E checks. Keeper: MenuBarMenuModelTests.testWAVConverterRowMapsCorrectly/testEmptyRegistryYieldsOnlyOutputInbox; QuickAccessRouterTests.testExecuteOpenToolPublishesNewRequest/testExecuteRevealOutputInboxSetsFlag; e2e quick_access_selected_tool and reveal markers check both final values.
- `testBothCommandsSequential`: Repeats menu/router owner tests and the executable quick-access E2E checks. Keeper: MenuBarMenuModelTests.testWAVConverterRowMapsCorrectly/testEmptyRegistryYieldsOnlyOutputInbox; QuickAccessRouterTests.testExecuteOpenToolPublishesNewRequest/testExecuteRevealOutputInboxSetsFlag; e2e quick_access_selected_tool and reveal markers check both final values.

### `NikoMusicCoreTests/ArchiveDiagnosticsGlobalWarningsPanelContextTests.swift`

- `testLineMatchesExportForGlobalWarning`: Synthetic export string duplicates the real builder/exporter parity path. Keeper: testInvalidRootScanGlobalWarningsPanelMatchesExporter calls linesMatchExport -> lineMatchesExport on nonempty warnings.

### `NikoMusicCoreTests/ArchiveDiagnosticsSearchPanelContextTests.swift`

- `testQueryLineMatchesExport`: Handwritten happy-path export repeats the retained real fixture-export checks. Keeper: testFixtureNeonSearchPanelMatchesExporter plus scan-warning/fuzzy fixtures; prefix mismatch and CRLF edge tests retained.
- `testMatchLinesMatchExport`: Handwritten happy-path export repeats the retained real fixture-export checks. Keeper: testFixtureNeonSearchPanelMatchesExporter plus scan-warning/fuzzy fixtures; prefix mismatch and CRLF edge tests retained.

### `NikoMusicCoreTests/ArchiveDiagnosticsSelectedSongPanelContextTests.swift`

- `testPanelNotesLineIncludesNotes`: Exact input and contains assertion duplicated by the stronger label test. Keeper: testPanelNotesLineUsesCompanionNotesLabel checks the identical notes payload, prefix and forbidden jargon.
- `testTitleLineMatchesExport`: Synthetic literal export strings duplicate real selected-song fixture export parity. Keeper: testFixtureBrokenFolderPanelMatchesExporter verifies all four helpers against actual exporter output, including nonempty notes.
- `testCprLineMatchesExport`: Synthetic literal export strings duplicate real selected-song fixture export parity. Keeper: testFixtureBrokenFolderPanelMatchesExporter verifies all four helpers against actual exporter output, including nonempty notes.
- `testWarningLinesMatchExport`: Synthetic literal export strings duplicate real selected-song fixture export parity. Keeper: testFixtureBrokenFolderPanelMatchesExporter verifies all four helpers against actual exporter output, including nonempty notes.
- `testNotesLineMatchesExport`: Synthetic literal export strings duplicate real selected-song fixture export parity. Keeper: testFixtureBrokenFolderPanelMatchesExporter verifies all four helpers against actual exporter output, including nonempty notes.

### `NikoMusicCoreTests/ArchiveDiagnosticsSkippedEntriesPanelContextTests.swift`

- `testLineMatchesExportForSkippedEntry`: Synthetic skipped entry export duplicates actual fixture export parity. Keeper: testFixtureScanSkippedEntriesPanelMatchesExporter checks nonempty two-entry output with linesMatchExport.

### `NikoMusicCoreTests/ArchiveDiagnosticsSkippedSearchPanelContextTests.swift`

- `testQueryLineMatchesExport`: Synthetic happy-path export duplicated by real exact/fuzzy skipped-search fixture exports. Keeper: testFixtureLooseFileSkippedSearchPanelMatchesExporter and testFixtureFuzzyLooseFileSkippedSearchPanelMatchesExporter; rejection/CRLF tests retained.
- `testMatchLinesMatchExport`: Synthetic happy-path export duplicated by real exact/fuzzy skipped-search fixture exports. Keeper: testFixtureLooseFileSkippedSearchPanelMatchesExporter and testFixtureFuzzyLooseFileSkippedSearchPanelMatchesExporter; rejection/CRLF tests retained.

### `NikoMusicCoreTests/ArchiveDiagnosticsScanCountsPanelContextTests.swift`

- `testCountsMatchExportForScanCountLines`: Hardcoded 9/1/1 scan-count export is duplicated by the real scanner/exporter fixture with those exact counts. Keeper: testFixtureScanCountsPanelMatchesExporter.

### `NikoMusicCoreTests/PreviewRankingTiebreakTests.swift`

- `testSelectedSongHeaderIncludesTiebreakCallout`: Identical ranked-song setup with a weaker substring assertion. Keeper: testSelectedSongHeaderDoesNotDuplicateTiebreakCallout asserts the same substring occurs exactly once.

### `FeatureDownloaderTests/DownloaderUATCoverageTests.swift`

- `testProgressMarkerParsingIsCovered`: UAT matrix repeats parser/stall/helper/handoff owner tests; local DownloadResult roundtrip has no independent logic. Keeper: DownloadProgressParsingTests.testParseNormalizedProgressFromNIKOProgressMarker; DownloadStallMonitorTests.testDownloadArgumentsReportPostProcessingInQuietMode/testStallsAfter120SecondsWithoutActivity/testStallErrorMessage; YtDlpHealthCheckerTests.testOutdatedWhenVersionOlderThan90Days; YtDlpDownloaderTests literal after_move marker; OutputHandoffTests existing WAV and downloader MP3 checks.
- `testStallPolicyIsCovered`: UAT matrix repeats parser/stall/helper/handoff owner tests; local DownloadResult roundtrip has no independent logic. Keeper: DownloadProgressParsingTests.testParseNormalizedProgressFromNIKOProgressMarker; DownloadStallMonitorTests.testDownloadArgumentsReportPostProcessingInQuietMode/testStallsAfter120SecondsWithoutActivity/testStallErrorMessage; YtDlpHealthCheckerTests.testOutdatedWhenVersionOlderThan90Days; YtDlpDownloaderTests literal after_move marker; OutputHandoffTests existing WAV and downloader MP3 checks.
- `testHelperHealthStatesAreRepresented`: UAT matrix repeats parser/stall/helper/handoff owner tests; local DownloadResult roundtrip has no independent logic. Keeper: DownloadProgressParsingTests.testParseNormalizedProgressFromNIKOProgressMarker; DownloadStallMonitorTests.testDownloadArgumentsReportPostProcessingInQuietMode/testStallsAfter120SecondsWithoutActivity/testStallErrorMessage; YtDlpHealthCheckerTests.testOutdatedWhenVersionOlderThan90Days; YtDlpDownloaderTests literal after_move marker; OutputHandoffTests existing WAV and downloader MP3 checks.
- `testStructuredOutputContractIsRepresented`: UAT matrix repeats parser/stall/helper/handoff owner tests; local DownloadResult roundtrip has no independent logic. Keeper: DownloadProgressParsingTests.testParseNormalizedProgressFromNIKOProgressMarker; DownloadStallMonitorTests.testDownloadArgumentsReportPostProcessingInQuietMode/testStallsAfter120SecondsWithoutActivity/testStallErrorMessage; YtDlpHealthCheckerTests.testOutdatedWhenVersionOlderThan90Days; YtDlpDownloaderTests literal after_move marker; OutputHandoffTests existing WAV and downloader MP3 checks.
- `testMediaHandoffAllowlistIsCovered`: UAT matrix repeats parser/stall/helper/handoff owner tests; local DownloadResult roundtrip has no independent logic. Keeper: DownloadProgressParsingTests.testParseNormalizedProgressFromNIKOProgressMarker; DownloadStallMonitorTests.testDownloadArgumentsReportPostProcessingInQuietMode/testStallsAfter120SecondsWithoutActivity/testStallErrorMessage; YtDlpHealthCheckerTests.testOutdatedWhenVersionOlderThan90Days; YtDlpDownloaderTests literal after_move marker; OutputHandoffTests existing WAV and downloader MP3 checks.

### `FeatureAudioRecorderTests/RecorderIntegrationTests.swift`

- `testFilenameOverrideRoundTrip`: Direct use-case call with a spaced WAV name duplicates the use-case owner, despite integration suite naming. Keeper: RecordSystemAudioUseCaseTests.testGenerateOutputFilenameWithOverride uses Custom Name.wav; casing, normalization and traversal tests remain.

### `FeatureAudioRecorderTests/AudioRecorderViewModelTests.swift`

- `testFilenameOverridePassedToUseCase`: Assigns then reads a public stored property; despite the name neither starts recording nor observes a use-case call. Keeper: Retain testMaxDurationAutoFinishFinalizesWAVAndInboxItem, real capture/save flows, and use-case filename rules; no forwarding assertion is being removed.
- `testMaxDurationPassedToUseCase`: Assigns then reads a public stored property; despite the name neither starts recording nor observes a use-case call. Keeper: Retain testMaxDurationAutoFinishFinalizesWAVAndInboxItem, real capture/save flows, and use-case filename rules; no forwarding assertion is being removed.

### `FeatureAudioRecorderTests/ResilientSystemAudioRecordingSessionTests.swift`

- `testFallbackIsNotUsedWhenCoreAudioProducesFrames`: Identical healthy backend fixture and start/stop path with only a subset of the keeper assertions. Keeper: testCoreAudioFirstHealthyBufferCompletesStartup also asserts fallback.startCount == 0, frames, core selection and start count.

### `FeatureDownloaderTests/YtDlpDownloaderTests.swift`

- `testDownloadEmitsNIKOProgressTemplate`: Identical download request/runner setup repeats arguments checked by the retry test; carry explicit --progress-template flag assertion into that keeper. Keeper: testDownloadAppliesBoundedNetworkRetries; DownloadStallMonitorTests.testDownloadArgumentsReportPostProcessingInQuietMode pins literal progress templates.

### `FeatureDownloaderTests/DownloaderTrustAndErrorTests.swift`

- `testCopyStringsAreNotEmpty`: All five nonempty checks are strict subsets of retained exact-string assertions. Keeper: testTrustNoticeIsDisplayedInView, testSourceURLIsDisplayedBeforeDownload, testOutputFolderIsDisplayedBeforeDownload, testDownloadButtonIsOnlyStartTrigger, testToolLabelIsDownloaderNotPromotional.

### `FeatureStemSeparationTests/DemucsMLXHealthCheckerTests.swift`

- `availability_whenEverythingAvailable_reportsReady`: Byte-identical executable fixture, runner response, production invocation and expectation. Keeper: availability_whenExecutableRunsWithoutCachedModels_reportsReady.

### `AppCoreTests/OutputInboxNotificationTests.swift`

- `testRefreshAvailabilityDoesNotPostWhenStatusesAreUnchanged`: Same real JSON store, available existing WAV, no-op refresh and inverted change-notification expectation. Keeper: OutputInboxStoreTests.testRefreshAvailabilityDoesNotNotifyWhenItemsAreUnchanged.

### `FeatureArchiveBrowserTests/ArchiveBoardEdgeAutoScrollerTests.swift`

- `testLeftEdgeScrollsToPreviousLeadingLane`: Identical initial update and targets == [2] assertion repeated by two stronger scroller lifecycle tests. Keeper: testRepeatedUpdatesDoNotImmediatelyRescroll and testLiveLeadingResyncStepsFromLiveWithoutImmediateRescroll. Right-edge scroller integration is retained.

### `NikoMusicCoreTests/ArchiveMetadataMergerTests.swift`

- `testSongVirtualTitleMutation`: Direct alias mutation repeats the effective title assertion reached through the real metadata merger. Keeper: testVirtualTitleOverridesDisplayTitle exercises ArchiveMetadataMerger.merge and verifies alias plus original folder preservation.

## Retained false positives

- UI host/no-crash tests retain a runtime construction boundary absent from source greps.
- Router initial-state defaults, feature metadata, notification names, hardware UAT,
  archive safety, migration, release, design and SwiftUI ownership guards remain.
- Panel text formatting assertions remain; fixture/export agreement alone does not
  prove the displayed text contains its payload.
- Right-edge scroller callback delivery remains; a pure direction-policy test
  cannot replace the scroller integration test.
- The explicit `--progress-template` argument assertion was carried into the
  existing downloader retry/argument keeper before its duplicate was removed.

## Reproduction and evidence

Use a normal checkout path under the home directory. The initial `/tmp` checkout
exposed existing `/tmp` versus `/private/tmp` fixture assumptions; those failed
runs were preserved and none of those tests was deleted. Rebuilding in the normal
checkout produced a green baseline. Both coverage runs use the same exclusions:

```sh
swift test --enable-code-coverage \
  --skip CoreAudioTapAdapterTests \
  --skip 'RecorderIntegrationTests/testMaxDurationAutoStop' \
  --skip 'RecorderIntegrationTests/testOutputFileHasCorrectFormat' \
  --skip 'RecorderIntegrationTests/testRecordingCapturesRealSystemAudio' \
  --skip 'RecorderIntegrationTests/testRecordingProducesOutputInboxItem'
./script/ci.sh
NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh
```

Final checks on the unchanged candidate test patch:

- Coverage baseline and candidate: **passed**; all 46 removals reconciled against
  SwiftPM discovery, with zero new test declarations.
- `./script/ci.sh`: **passed**, including recorder deterministic gate, malformed-AX
  self-test, core self-test, CLI export, release and source-distribution checks.
- `NMH_STRICT_UI_E2E=1 ./script/e2e_user_smoke.sh`: **passed** with AX-visible
  first-run UI, screenshot inspection, both quick-access final-state markers,
  recorder inbox flow and unchanged Cubase/Ableton fixture archives. No AX skip.
- Independent Cursor Grok preservation review: **ACCEPT**, no material gap or
  required restoration. The reviewer compared the actual removed assertions to
  keepers; coordinator-owned execution above remains separate evidence.
- `git diff --check`, UAT matrix references, before/after test inventory and hashes
  for all 503 production/package/script files: **passed**.

The source patch reviewed and tested has SHA-256
`31b3854f9b3eee784f649882da5ac5f17980b7efc761a5fc968d6a4deb44e647`.
This identifies the test/UAT-matrix diff; this audit report and local evidence
are recorded separately. Both instrumented XCTest runs took about 62 seconds;
these single runs establish no meaningful speed improvement.

Local evidence is retained under `.codex/audits/test-value-2026-09-26/`: before/after
logs, test inventories, coverage exports/comparison, production hashes, exact
candidate ledger with introduction history, and external worker handoffs.
Discovery used bounded Muse CLI workers, with Cursor Grok for independent preservation review; acceptance remains the coordinator's. Seven worker calls were used, including two partial discoveries that were narrowed into follow-up packets.

Follow-ups: the worktree-path fixture assumptions deserve a separate portability
fix. No conclusions about installed hardware capture or published release state
are made. Changes are uncommitted and have not been pushed or released.
