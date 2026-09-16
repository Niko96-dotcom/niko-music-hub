# NMH-018 GUI Accept (2026-09-16 ~00:05 CEST)

Shared proof: `dist/gui-accept/NMH-sev3-20260916-235736/` (fixture CubaseArchive via `NIKO_MUSIC_HUB_FIXTURE_ROOT`, isolated suite `NikoMusicHubGUIAcceptSev3.18493CF1-9A0C-41E9-B661-A3265D5A17B7`, `DRY_RUN_OPEN=1`, no live ~/Music writes; settings left at suite default).

## Sidebar selection is exposed to accessibility

| Check | Result |
|-------|--------|
| Selected Archive Browser has value=Selected | **PASS** (`ax-018.txt`) |
| After Tools→BPM, BPM Tapper value=Selected | **PASS** (`ax-018-bpm.txt`) |
| Helper Tools not a selected tool-set item | **PASS** — no hub_tool_helper; Settings is separate |

VoiceOver “selected” maps to AX value=Selected on tool buttons.

## Verdict

**fixed**

Proof dir shared sev3 session. App binary tip at launch: v1.5.4+92fa3a0.
