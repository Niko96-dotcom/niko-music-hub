# Public Release Real UAT - 2026-05-26

This pass replaces the earlier overclaimed UAT with live app evidence from the real SwiftUI app launched through `./script/build_and_run.sh`.

## Environment

- App: `dist/NikoMusicHub.app`
- Launch path: `./script/build_and_run.sh`
- Real Cubase/archive root: `/Users/nikolaymohr/Downloads/Projekte`
- Shared UAT output folder: `/Users/nikolaymohr/Downloads/NikoMusicHub-UAT-Output-20260526-093535`
- Primary evidence roots:
  - `/tmp/niko-music-hub-public-uat-20260526-093535`
  - `/tmp/niko-music-hub-public-uat-20260526-101834`

## Evidence Table

| Area | Status | Real user action | Evidence |
|------|--------|------------------|----------|
| Window layout | Passed | Captured the launched app with window-only screenshots at default, wide, and minimum practical sizes. Fixed the shell padding so sidebar/content no longer sits against the window edge. | `screens/initial-window.png`, `screens/after-padding-default.png`, `screens/after-padding-wide.png`, `screens/after-padding-min-size.png`, `logs/ax-after-padding.txt` under `/tmp/niko-music-hub-public-uat-20260526-093535` |
| Archive Browser | Passed | Clicked Add Root, selected `/Users/nikolaymohr/Downloads/Projekte`, scanned through the UI, searched `cxloe`, selected `CXLOE`, inspected the main preview and CPR versions, and pressed Open Latest CPR in dry-run mode. | `screens/archive-root-added.png`, `screens/archive-after-scan.png`, `screens/archive-search-cxloe-keyboard.png`, `screens/archive-selected-cxloe-detail.png`, `screens/archive-detail-reordered.png`, `screens/archive-open-latest-dryrun.png`, `logs/ax-after-open-latest-dryrun.txt` |
| Archive read-only proof | Passed | Took archive stat snapshots before and after scanning/opening. | `snapshots/archive-before.stat` and `snapshots/archive-after-open.stat` compare equal; `ARCHIVE_UNMODIFIED=yes` |
| Archive recovery state | Passed | Searched a no-match term after the real scan. | `screens/archive-search-no-match.png` |
| BPM Tapper | Passed | Clicked the tap surface repeatedly, produced a plausible tempo, switched half/double/original modes, copied BPM, saved it to recent tempos, reset the tapper, and cleared history. | `screens/bpm-after-taps.png`, `screens/bpm-half-time.png`, `screens/bpm-double-time-corrected.png`, `screens/bpm-original-restored.png`, `logs/bpm-copy-pasteboard-2.txt`, `screens/bpm-saved-recent-2.png`, `screens/bpm-reset-2.png`, `screens/bpm-clear-history-confirmed-2.png` under `/tmp/niko-music-hub-public-uat-20260526-101834` |
| WAV Converter | Passed | Added `/Users/nikolaymohr/Downloads/Medien/Neue Aufnahme 14.m4a` through the app file picker and converted it to the selected output folder. | `screens/converter-after-convert-2.png`, `logs/converter-afinfo.txt` |
| WAV output metadata | Passed | Verified the generated WAV files with `afinfo`. | Input: 39.253333 sec, 2 ch, 48000 Hz AAC. Outputs: 39.253333 sec, 2 ch, 44100 Hz, 24-bit LPCM WAV, about 9.9 MB each. |
| Recorder | Blocked by local permission | Used the Recorder UI Start Recording action. The app first exposed a missing `NSMicrophoneUsageDescription` crash; that was fixed in the generated app Info.plist. Retesting showed the macOS microphone consent sheet and then the app's Permission Required recovery state after permission was not granted. | Crash: `~/Library/Logs/DiagnosticReports/NikoMusicHub-2026-05-26-103913.ips`. Recovery evidence: `screens/recorder-open-system-settings-recovery.png`, `screens/recorder-after-deny-permission-fullscreen.png`, `logs/ax-recorder-after-deny-permission.txt`. No recorder WAV was produced, so recorder is not fully passed. |
| Downloader | Passed | Used the Downloader UI with public YouTube URLs. Verified one unavailable URL reports a concrete failure, then downloaded `https://youtu.be/jNQXAC9IVRw` through `yt-dlp` into the shared output folder. | Failure: `screens/downloader-after-axpress-download.png`. Success: `screens/downloader-final5-after-download.png`, `logs/ax-downloader-final5-after-download.txt`, `logs/downloader-ffprobe-me-at-zoo-mp4.json` |
| Downloader metadata | Passed | Verified the downloaded media with `ffprobe`. | `/Users/nikolaymohr/Downloads/NikoMusicHub-UAT-Output-20260526-093535/Me at the zoo.mp4`: 18.947483 sec, 629172 bytes, H.264 320x240 video, AAC 44100 Hz stereo audio. |
| Helper health | Passed | Verified helper availability in the live app and from local binaries. | `yt-dlp` at `/opt/homebrew/bin/yt-dlp` version `2026.03.17`; `ffmpeg` at `/opt/homebrew/bin/ffmpeg` version `8.1.1`. Helper labels remained visible in the live UI evidence. |
| Shared output folder | Passed | Chose `/Users/nikolaymohr/Downloads/NikoMusicHub-UAT-Output-20260526-093535` through the UI and verified converter/downloader outputs landed there. Recorder could not produce output because recording permission was not granted. | `logs/ax-output-folder-chosen.txt`, output folder listing, converter and downloader metadata logs. |
| Output Inbox | Passed with recorder exception | Verified converted WAV files and downloaded media appear in the live Output Inbox with available status and reveal/drag-out surfaces where visible. | `screens/converter-after-convert-2.png`, `screens/downloader-final5-after-download.png` |
| Open/reveal/export flows | Passed with recorder exception | Archive Open Latest CPR was tested in dry-run mode, converter outputs exposed Reveal and Drag WAV, downloader output file was verified at the shared output path, and diagnostics/export smoke remains covered by the scripted E2E gate. Recorder open/reveal could not be completed without a recording. | Archive dry-run evidence, converter screenshot, downloader output path and `ffprobe`, final scripted gates. |
| Empty/invalid/recovery states | Passed | Verified archive no-match search, downloader unavailable-video failure, BPM reset/clear recovery, and recorder permission recovery. | Archive no-match screenshot; downloader failure screenshot; BPM reset/clear screenshots; recorder permission screenshots. |

## Bugs Found And Fixed

- The app shell had insufficient outer padding at the window edge. The shell now adds comfortable outer spacing around the sidebar and content.
- Large real archive details pushed CPR controls below hundreds of previews. Song detail now keeps the main preview and CPR versions above a capped preview list.
- The generated app bundle lacked `NSMicrophoneUsageDescription`, causing a TCC crash when requesting recorder permission. The launcher-generated Info.plist now includes the microphone usage description.
- Downloader success did not reliably hand output files to Output Inbox. Completed downloads now log destination paths for inbox ingestion.
- Real `yt-dlp` downloads could hang on large/default formats. Downloads now use bounded network retries, a lower-resolution format selector, and a hard external-process timeout.

## Remaining Blocker

Recorder is explicitly blocked on this Mac until the user grants the local macOS microphone/audio-capture permission for `NikoMusicHub`. This UAT does not mark Recorder fully passed because no real recording WAV was produced.

## Final Gates

- `./script/ci.sh` passed after the last code and documentation changes.
- `./script/e2e_user_smoke.sh` passed after the last code and documentation changes.
- `./script/build_and_run.sh --verify` passed after the last code and documentation changes.
- Post-verify live UI evidence: `/tmp/niko-music-hub-public-uat-20260526-101834/screens/final-post-verify-live-ui.png` and `/tmp/niko-music-hub-public-uat-20260526-101834/logs/ax-final-post-verify.txt`.
