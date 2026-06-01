# Release Validation

This document records the public validation posture for Niko Music Hub v0.1.0. It intentionally avoids private archive paths, local evidence directories, and personal file names.

## Automated Gates

| Gate | Scope |
| --- | --- |
| `./script/ci.sh` | Builds the Swift package, runs deterministic tests, and runs `NikoMusicCoreSelfTest`. |
| `./script/e2e_user_smoke.sh` | Runs fixture archive scan/search/open flow through the app binary and verifies public first-run UI. |
| `./script/build_and_run.sh --verify` | Builds and verifies the native app bundle. |

## Manual UAT Coverage

| Area | Result |
| --- | --- |
| App launch and layout | Verified with the native app bundle at default, wide, and compact window sizes. |
| Archive Browser | Verified root selection, scan, search, song detail, main preview ranking, CPR versions, and dry-run latest CPR open. |
| Archive safety | Verified before/after snapshots of the scanned archive stayed unchanged. |
| BPM Tapper | Verified taps, half-time, double-time, copy, save, reset, and clear history flows. |
| WAV Converter | Verified local audio input conversion to Cubase-ready WAV output. |
| Recorder | Verified live system-audio capture on a supported macOS setup after granting local permission. |
| Downloader | Verified helper health, a user-facing failure state, and a successful public URL download. |
| Output Inbox | Verified converter, recorder, and downloader output handoff. |
| Recovery states | Verified no-match archive search, downloader failure, BPM reset/clear, and recorder permission recovery. |

## Known Release Boundaries

| Boundary | Status |
| --- | --- |
| GitHub Actions | Not configured. Local macOS gates are the release truth. |
| Signing and notarization | Not included in v0.1.0. |
| Recorder automation | Host-only recorder tests remain manual because macOS hardware and privacy state vary by machine. |
| Archive mutation | Out of scope. The app is a recall and utility layer, not a file manager. |
