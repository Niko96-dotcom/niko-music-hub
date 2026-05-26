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
  - `/tmp/niko-music-hub-recorder-diagnostics-20260526-172844`
  - `/tmp/niko-music-hub-final-post-verify-20260526-173934`

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
| Recorder | Passed live capture | Launched the signed app through `./script/build_and_run.sh --verify`, selected Recorder, pressed Start Recording in the real UI, played an audible generated tone and system beeps through `Mac Studio-Lautsprecher`, pressed Stop in the real UI, and verified the resulting WAV plus Output Inbox entry. Earlier failed 4 KB headers are still present as failed evidence only; they are not counted as successful output. | `/tmp/niko-music-hub-recorder-diagnostics-20260526-172844/screens/after-start.png`, `screens/after-stop.png`, `logs/new-files.txt`, `logs/latest-afinfo.txt`, `logs/latest-ffprobe.txt`, `logs/latest-volumedetect.txt`, `logs/ax-after-stop.txt` |
| Recorder metadata | Passed | Verified the live recording with `afinfo`, `ffprobe`, and `ffmpeg volumedetect`. | `/Users/nikolaymohr/Downloads/NikoMusicHub-UAT-Output-20260526-093535/Recording 2026-05-26 17-29-33.wav`: 12.991655 sec, 2 ch, 44100 Hz, 24-bit LPCM WAV, 3,441,688 bytes, 3,437,592 audio bytes, 572,932 packets. `volumedetect`: 1,145,864 samples, mean volume -32.7 dB, max volume -27.2 dB. |
| Recorder reveal/open | Passed | From the Recorder success card, pressed Reveal and Open. Finder opened the shared output folder and the system opened the WAV in Music. | `/tmp/niko-music-hub-recorder-diagnostics-20260526-172844/logs/recorder-reveal-open.txt`, `screens/after-reveal-open.png` |
| Downloader | Passed | Used the Downloader UI with public YouTube URLs. Verified one unavailable URL reports a concrete failure, then downloaded `https://youtu.be/jNQXAC9IVRw` through `yt-dlp` into the shared output folder. | Failure: `screens/downloader-after-axpress-download.png`. Success: `screens/downloader-final5-after-download.png`, `logs/ax-downloader-final5-after-download.txt`, `logs/downloader-ffprobe-me-at-zoo-mp4.json` |
| Downloader metadata | Passed | Verified the downloaded media with `ffprobe`. | `/Users/nikolaymohr/Downloads/NikoMusicHub-UAT-Output-20260526-093535/Me at the zoo.mp4`: 18.947483 sec, 629172 bytes, H.264 320x240 video, AAC 44100 Hz stereo audio. |
| Helper health | Passed | Verified helper availability in the live app and from local binaries. | `yt-dlp` at `/opt/homebrew/bin/yt-dlp` version `2026.03.17`; `ffmpeg` at `/opt/homebrew/bin/ffmpeg` version `8.1.1`. Helper labels remained visible in the live UI evidence. |
| Shared output folder | Passed | Chose `/Users/nikolaymohr/Downloads/NikoMusicHub-UAT-Output-20260526-093535` through the UI and verified converter, downloader, and recorder outputs landed there. Failed 4 KB recorder headers remain documented as failed attempts, while the passed recording is the non-empty 17:29:33 WAV. | `logs/ax-output-folder-chosen.txt`, converter and downloader metadata logs, recorder passed evidence under `/tmp/niko-music-hub-recorder-diagnostics-20260526-172844` |
| Output Inbox | Passed | Verified converted WAV files, downloaded media, and the successful recorder WAV appear in the live Output Inbox with available status and reveal/drag-out or reveal/open surfaces where visible. | `screens/converter-after-convert-2.png`, `screens/downloader-final5-after-download.png`, `/tmp/niko-music-hub-recorder-diagnostics-20260526-172844/logs/ax-after-stop.txt` |
| Open/reveal/export flows | Passed | Archive Open Latest CPR was tested in dry-run mode, converter outputs exposed Reveal and Drag WAV, downloader output file was verified at the shared output path, Recorder Reveal/Open was exercised from the success card, and diagnostics/export smoke remains covered by the scripted E2E gate. | Archive dry-run evidence, converter screenshot, downloader output path and `ffprobe`, recorder `logs/recorder-reveal-open.txt`, final scripted gates. |
| Empty/invalid/recovery states | Passed | Verified archive no-match search, downloader unavailable-video failure, BPM reset/clear recovery, and recorder permission recovery. | Archive no-match screenshot; downloader failure screenshot; BPM reset/clear screenshots; recorder permission screenshots. |

## Bugs Found And Fixed

- The app shell had insufficient outer padding at the window edge. The shell now adds comfortable outer spacing around the sidebar and content.
- Large real archive details pushed CPR controls below hundreds of previews. Song detail now keeps the main preview and CPR versions above a capped preview list.
- The generated app bundle lacked `NSMicrophoneUsageDescription`, causing a TCC crash when requesting recorder permission. The launcher-generated Info.plist now includes the microphone usage description.
- Recorder stop/finalize could stall and empty WAV headers could be treated as successful enough for UI handoff. Manual stop now finalizes through the view model, and zero-frame recordings are rejected with a verification failure.
- CoreAudio process taps were not delivering usable public-release recordings because the aggregate was not bound to a stable explicit tap UUID, the launched app was ad-hoc signed without the local development audio entitlement, and the writer converted into an on-disk 24-bit format instead of the `AVAudioFile.processingFormat` required for writes. The launcher now signs with a stable Apple Development identity when available, includes audio-input entitlement, the tap uses an explicit UUID and the audible system output device, and the writer converts into the processing format while preserving the 24-bit WAV file format.
- Downloader success did not reliably hand output files to Output Inbox. Completed downloads now log destination paths for inbox ingestion.
- Real `yt-dlp` downloads could hang on large/default formats. Downloads now use bounded network retries, a lower-resolution format selector, and a hard external-process timeout.

## Remaining Blocker

No public-release blocker remains from this UAT pass. The earlier Recorder failure is retained above as historical failed evidence; the current passed evidence is the live UI recording at `/Users/nikolaymohr/Downloads/NikoMusicHub-UAT-Output-20260526-093535/Recording 2026-05-26 17-29-33.wav`.

## Final Gates

- `./script/ci.sh` passed in the final gate run after the Recorder code changes.
- `./script/e2e_user_smoke.sh` passed in the final gate run after the Recorder code changes.
- `./script/build_and_run.sh --verify` passed in the final gate run after the Recorder code changes.
- Post-verify live UI evidence: `/tmp/niko-music-hub-final-post-verify-20260526-173934/screens/final-post-verify-live-ui.png` and `/tmp/niko-music-hub-final-post-verify-20260526-173934/logs/ax-final-post-verify.txt`.
