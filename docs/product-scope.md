# Product Scope

Niko Music Hub v0.1.0 is a native macOS app for local music-production workflows around Cubase archives.

## Included

| Capability | Included behavior |
| --- | --- |
| Archive root selection | Add one or more folders that contain song/project folders. |
| Archive scan | Treat each immediate child folder as a song, collect `.cpr` versions, collect preview candidates, and surface scan warnings. |
| Latest CPR | Select the most recently modified `.cpr` as the default open target. |
| Preview ranking | Pick a main preview from mixdown/location/name/version/extension/duration/recency signals. |
| Search | Match song titles, folder names, CPR filenames, preview filenames, warning text, and skipped root entries. |
| Diagnostics | Export support summaries and panel rows that match the same scan/search/ranking data. |
| BPM Tapper | Estimate tempo from taps, adjust time feel, save history, and copy values. |
| WAV Converter | Convert selected audio files into Cubase-ready WAV presets. |
| Recorder | Capture system audio to WAV on supported macOS setups. |
| Downloader | Download user-provided supported URLs through `yt-dlp`. |
| Output Inbox | Collect generated converter, recorder, and downloader outputs in one place. |

## Not Included

| Non-goal | Reason |
| --- | --- |
| Deep `.cpr` parsing | Folder and filesystem metadata are enough for v0.1.0 recall workflows. |
| File management inside archives | The app must not rename, move, delete, or rewrite real music files. |
| Cloud sync or public sharing | The product is local-first and single-user. |
| DAW plugin integration | The app is a companion utility, not a Cubase extension. |
| Embedded web runtime | The product is native SwiftUI/AppKit, not Electron. |
| GitHub Actions as release truth | Local macOS gates are authoritative for now. |

## Done State

| Gate | Status |
| --- | --- |
| Native app target named `NikoMusicHub` | Done |
| Archive browser wired as a registered tool | Done |
| Existing outside-Cubase tools preserved | Done |
| Fixture-first core and feature tests | Done |
| Read-only archive policy | Done |
| User-style E2E smoke | Done |
| Public docs and sanitized repository surface | Done |

## Future Ideas

| Idea | Notes |
| --- | --- |
| Signed/notarized release artifact | Needs Apple Developer distribution setup. |
| Manual preview overrides | Keep app-owned metadata, never rename source files. |
| Richer archive shelves | Examples: recently bounced, missing CPR, strongest previews. |
| Broader helper management | Better in-app guidance for installing/updating `ffmpeg` and `yt-dlp`. |
| Optional metadata cache | App-owned cache only, outside music roots. |
