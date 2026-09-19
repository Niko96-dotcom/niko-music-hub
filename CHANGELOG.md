# Changelog

## 1.6.1 - 2026-09-19

- Keep Project Vault approval bound to the intended project and source through confirmation, queueing and retries. Settings changes cannot turn a copy-only operation into removal.
- Preserve truthful cancellation and recovery states, recheck durable archive and recovery-journal evidence before removing Active, and revoke queued Done actions when undone.
- Recover inaccessible library folders independently while preserving root identities and disabled folders.
- Return verified existing downloads to the Output Inbox and report actual download failures accurately.
- Refresh large output histories off the main thread and improve archive search and Vault catalog reconciliation without trimming history.
- Build releases from isolated pinned source, freeze exact acceptance evidence, and enforce complete release gates and production update-key continuity.
- Refresh the public product overview with screenshots of the current native interface.

## 1.6.0 - 2026-09-18

- Rebuild BPM Tapper, WAV Converter, Audio Recorder, Downloader, and Stem Separation on one layout: the work area on the left, the tool's settings and its main action in a fixed panel on the right. Titles, cards, option controls, and buttons now sit in the same place on every page.
- Move between tools and archive pages with Back and Forward in the window bar (Command-[ and Command-]), and switch the archive between board and list with a single button that stays in one place.
- Show the Output Inbox reliably: the toggle now follows your choice instead of a window-width rule that could hide the panel with no way back.
- Match the tools sidebar, the tool settings panel, and the Output Inbox in width and material, so the window reads as one workspace.
- Replace the multi-step recording length picker with a slider, and group related options into single controls instead of loose chips.
- Remove idle status lines, repeated helper text, and unused explanation throughout, so each page shows the object you work with and what changed.
- Keyboard focus, Full Keyboard Access, VoiceOver order, Full Screen, window restoration, and menu commands across the shell, Song menu, and tools now follow Apple's Human Interface Guidelines, with the system's blue focus ring replaced by the app's own quiet ring.
- Move the board's empty-stage option into Settings, next to the other archive preferences.
- Give the window the Codex-style shell: the sidebar, tool panel, and Output Inbox use the system sidebar material (a hint of the desktop shows through, nothing behind the window stays readable), the separate title strip is gone so each column runs to the window edge, and the window controls sit lower with more air.
- Retune dark mode to a warm neutral gray instead of blue-black, tighten sidebar rows and captions to the Codex rhythm, lighten the row icons, and stop showing a focus ring on the sidebar toggle at launch.
- Fix Audio Recorder recordings playing 8.8 % too fast and a semitone and a half sharp whenever the Mac's output device runs at 44.1 kHz: frames are now labeled with the rate they are actually captured at, so a recorded 440 Hz tone is a 440 Hz tone in the file.
- Explain why the app asks for access to Documents, Desktop, Downloads, external and network drives in the macOS permission prompts.
- Harden the release pipeline: prove hardened runtime, Team ID and the exact entitlement set on every component before upload, refuse a build number the update feed would never offer, refuse stray local release tags and test-feed overrides, and require acceptance testing on a Developer ID build.

## 1.5.4 - 2026-09-15

- Restore linked historical archives into Active Projects while preserving project identity, metadata, and the original archive.
- Choose a CPR or ALS version before restoring, and choose another destination when an existing folder must be kept.
- Show archive availability and live restore stages, with clear recovery actions for interrupted transfers and failed project opening.
- Keep the selected version through restore recovery and retry, refresh recovered projects without relying on filesystem events, and clear outdated archive messages after restoring.

## 1.5.3 - 2026-09-15

- Guide archived project versions to the appropriate restore or Finder action instead of offering an open action that cannot succeed.
- Improve song search relevance while retaining typo and abbreviation matching, preserve ranked results within Board columns, and show the filtered result count.
- Filter preview candidates by filename and distinguish same-name files with their relative folders, while preserving playback, Compare position, and Main selection.

## 1.5.2 - 2026-09-15

- Preserve original project and file names when archiving through providers that cannot store trailing spaces or certain special characters. Restoring a project reproduces its original names.
- Safely retry affected legacy archives after verifying the Active source, while retaining previous staging copies for recovery.
- Show linked existing archive folders in the browser with their actual availability and a Show in Finder action for online-only files.
- Prevent duplicate Project Vault identities caused by stale scan data or incomplete project-file inventories, while preserving exact timestamp precision and existing history.
- Include the Sparkle updater's complete license notices in the app and correct the dependency inventory.
- Remove unused types left behind by earlier implementations.

## 1.5.1 - 2026-09-13

- Show "now" instead of "in 0 s" for a download or recording that was just added to the Output Inbox.
- Clean up leftover temporary files next to the Output Inbox index that an interrupted save could leave behind.
- Stop test and review runs from leaving empty preference files behind.
- Harden the release pipeline: refuse to start on a locked screen or without a reachable notary service, retry notary uploads, check secure timestamps on every nested component before upload, and allow a full release rehearsal before the version tag exists.
- Make the incremental archive-rescan tests deterministic instead of timing-based.

## 1.5.0 - 2026-09-11

- Update Niko Music Hub from inside the app: a daily automatic check, Check for Updates… in the app menu, and an Updates section in Settings. Downloads come from a signed release feed and are verified before anything is installed.
- Replace the per-row, detail, and board transports with one persistent preview player that keeps playing while you switch tools or songs.
- Add play buttons to song rows and board cards, and a Previews tab in song detail for choosing the main preview and comparing mixdowns at the same elapsed moment.
- Pause previews automatically while the Recorder captures system audio, so a preview can never end up inside a recording.
- Reorganise song detail around a main-project card, Versions / Previews / Song info / Plugins tabs, and a details rail; Project Vault moves to a sheet unless it needs attention.
- Let empty board stages collapse to a compact rail, narrow the song list, and alternate list and detail below the split-view width.
- Quiet the tool chrome: palette-derived hover fills that work in the light appearance, plain tool titles, a leaner converter intake, and ½ / 1× / 2× tempo chips.
- Generate and verify the update feed as part of every public release, checking both signatures against the key embedded in the shipped app.
- Remove the retired waveform peak loader, transport bar, and metadata chip row, and keep the release-notes check current across version bumps.
- Fix "Convert preview" doing nothing once the WAV Converter had already been opened in the same session; the handoff now queues the file every time.

## 1.4.3 - 2026-09-10

- Add Ableton project support alongside Cubase.
- Preserve Project Vault Keep Local choices when changing settings and retain metadata for archived projects.
- Queue Project Vault operations so archiving and restoring several songs runs in order instead of competing.
- Make Archive Now remove verified Active copies, keep backups separate, and bind archive actions to each song's own folder.
- Explain failed restores, allow safe retries after repairing a backup, and keep backup acknowledgements visible and revocable.
- Guard Vault source removal more carefully by honoring open-file checks before deleting and keeping safe refusals retryable.
- Fix Vault recovery scheduling that could block manual archiving, and wake persisted recovery at its due date.
- Improve Dropbox archive verification and prevent opening projects that contain no project file.
- Improve YouTube download compatibility and recovery from temporary HTTP 403 errors.
- Name demo cards from the delivered artist and title, and rank complete, current bounces ahead of older ones while preserving manual picks.
- Improve archive browsing with clearer board hierarchy, better song row selection, and faster loading.
- Remove unused interface code and redundant wrappers, and strengthen behavioral coverage of backup and restore workflows.

## 1.4.2 - 2026-08-01

- Clean stale project metadata and close the release-preparation debt carried forward from 1.4.1.
- Harden public artifact provenance with an explicit arm64/macOS 14.2 platform contract, exact artifact size, signing, and manifest validation.
- Preserve fail-closed local release engineering across local-only and public workflows, including exact-commit checks and hosted-artifact verification.

## 1.4.1 - 2026-07-22

- Harden Project Vault Done-trigger archiving, Keep Local restore behavior, canonical path matching, and Cubase activity detection.
- Add an end-to-end Friends workflow covering archive, verified restore, Keep Local, and relaunch recovery.
- Show the exact build ID and source commit in the app so an installed build can be identified independently of its marketing version.
- Preserve fail-closed local release engineering and exact installed-build verification for the 1.4.1 delivery.

## 1.4.0 - 2026-07-13

- Establish fail-closed local release engineering for signed/notarized macOS DMG releases.
- Add release version verification, public tree hygiene, artifact validation, checksums, manifests, and installed bundle verification.
