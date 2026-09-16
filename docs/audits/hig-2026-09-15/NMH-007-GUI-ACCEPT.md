# NMH-007 GUI Accept (2026-09-16 ~00:05 CEST)

Shared proof: `dist/gui-accept/NMH-sev3-20260916-235736/` (fixture CubaseArchive via `NIKO_MUSIC_HUB_FIXTURE_ROOT`, isolated suite `NikoMusicHubGUIAcceptSev3.18493CF1-9A0C-41E9-B661-A3265D5A17B7`, `DRY_RUN_OPEN=1`, no live ~/Music writes; settings left at suite default).

## BPM readout accessibility name includes value

| Check | Result |
|-------|--------|
| Readout AX description=Current BPM | **PASS** (`ax-007.txt` / `ax-007-after.txt`) |
| After taps, AX value is numeric BPM | **PASS** — value=180 with description=Current BPM |

VoiceOver would announce description + value (`Current BPM, 180`). Unattended AX used instead of enabling VO.

## Verdict

**fixed**

Proof dir shared sev3 session. App binary tip at launch: v1.5.4+92fa3a0.
