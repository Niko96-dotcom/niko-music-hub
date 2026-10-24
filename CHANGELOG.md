# Changelog

## Unreleased

- Remove "Archive automatically", its "After *n* days untouched" and "Or when less than *n* GiB is free" steppers, and the login-item row with its warning from Settings → Project Vault: they promised background archiving that never ran. Marking a song Done still makes a verified copy that keeps the Active folder. Open at login stays in General, without its subtitle "Lets Project Vault archive while you’re away".
- Name the real reason when a Done archive is refused (Emergency Stop, Project Vault off, a missing folder, the Keep Local review, "After archiving" set to keep the Active copy, or the missing backup confirmation) instead of "Automatic archiving is turned off." When the Vault free-space settings cannot be checked, the message no longer names the removed inactivity setting.
- Drop the `automatic_archiving`, `automation_permitted`, `inactivity_days` and `minimum_free_space_gib` lines from Project Vault diagnostics. Settings and recovery copies saved by 1.8.1 still load.

## 1.8.1 - 2026-10-21

- Download online-only Dropbox files when restoring a Project Vault copy. Retry starts a fresh download after a provider error and resumes failed or stopped restores, including after restarting the app; the verified copy and song metadata stay intact.
- Keep a loose Cubase or Ableton song's title, notes, aliases and workflow history when a newer project version appears, and retain Project Vault identity across ordinary project saves.
- Make large archive browsing and rescans lighter: reuse native board rows, keep the board mounted during song-detail visits, share unchanged catalog data, and move scan and cache work off the main thread.
- Allow Quit while a workflow sheet is open. Explain recorder permission waits and a cancelled start, show the resolved download title, and keep relative dates in English throughout the interface.
- Refresh the footer after undoing a paused Done action, distinguish finalizing a Vault copy from waiting for cloud upload, and make archive confirmation and restore instructions match the current controls.
- Isolate development and automated-test launches from the installed app's settings, including AppKit and update preferences.
- Keep an uneven BPM tap out of the estimate without interrupting tapping with an outlier message.

## 1.8.0 - 2026-10-18

- Keep every configured music folder (Active, Archive and library) write-protected for tool output while Project Vault is off: the WAV Converter, Downloader, Audio Recorder, Stem Separation, the Settings output picker, Export Index, Export Diagnostics, New Song and recovery copies now refuse those folders, follow a folder that was renamed or moved in Finder, and also catch a path that reaches a music folder through a broken symbolic link.
- Refuse Archive Now, Done, New Song, exports, recordings, conversions, downloads and stem runs when saved settings cannot be read, instead of carrying on with default settings; a Keep Local song no longer shows as ready to free space in that state, and launch at login is left as it is.
- Say "Settings couldn't be read" in plain words when settings no longer load, instead of showing "The data couldn't be read because it isn't in the correct format." or blaming the chosen folder.
- Refuse song edits when the song database cannot be opened, instead of showing them as saved and losing them at the next rescan; a refused title, note or alias edit now stays unsaved in the song detail.
- Stop archiving a project when its move to Done was not saved, and add no Undo or Redo step for a status or note change that did not happen.
- Stop offering Recover after an archive fails before it starts removing the Active copy; Recover could replace newer Active work with the older Vault copy.
- Unpin a restored project completely when Keep Local is turned off, so Free up space is offered again.
- Keep a project restorable after a temporary read error; Retry now completes instead of the restore staying blocked.
- Apply a project identity review only to the two projects it was about; when three or more catalog entries share one folder, ask about each pair instead of merging or unlinking all of them at once.
- Stop failing an archive copy with "Project files changed while archiving" when Finder only updated a folder's hidden view settings, and name a symbolic link inside a project as the reason when it blocks the copy.
- Export recovery copies to exFAT, FAT and network (SMB) drives; a recovery export also says when the Vault is busy or settings cannot be read, and its default folder name uses the same date format on every calendar and locale. Test Restore no longer updates "Last verified"; only real Vault checks set it.
- Make Done a plain status change, with Undo, while Project Vault is off or not set up, instead of a card that would not move, and show "Archive this project?" at once from the song detail's "Manage storage" sheet instead of only after that sheet was closed.
- Make Choose Folder in the restore sheet create the project folder inside the folder you pick, with a free name when that name is taken, instead of giving a destination the sheet then refused.
- End an automatic archive pass when it is stopped, and show plain failure messages instead of internal error text.
- Keep an unavailable Vault folder in Settings exactly once, instead of adding another copy of it on each change.
- Keep a working stem helper when a reinstall fails or is cancelled, remove old helper environments that only took up disk space, and report failed helper downloads as download failures.
- Keep typed spaces in the archive search field and in song notes and metadata fields; a space no longer dropped everything typed after it or toggled the preview.
- Keep excluded folders out of the archive after an automatic rescan, rescan when a music folder is renamed or moved, keep file watching alive after an empty change batch, stop a cancelled full scan from starting again by itself, and drop a deleted loose project under a /private path.
- Keep valid matches in filtered archive searches, find typos that cross a word boundary (such as "mysnog" for "My Song Remix"), and stop short words from matching almost every skipped item.
- Detect project versions without mistaking a tempo such as "140 BPM" or a day-first date for a version, keep a real folder name when a delivery file is only named "V2" or "Mix 2", and explain preview choices that were decided by the song title.
- Detect the key of mixdowns correctly (labels were mirrored and leaned toward minor keys), and find a tempo for slow songs and mixdowns with long kicks, which often got no tempo before.
- Make skip and seek work while an archive preview is still loading, instead of leaving the player silent or stuck, and say why Open Preview (P) did nothing: the song has no main preview, or the file is missing or blocked.
- Add Show in browse to a project version that was hidden from browse, so hiding it can be undone in the app, and report a New Song as created when only its template project fails to open; a template that contains a symbolic link or special file gets its own message.
- Show the newest change first in a song's status history, refresh the Plugins tab when the main project changes, keep duplicate hints in a stable order, and leave hidden, removed and finished songs out of the Analytics stage times.
- Clear skipped items and folder warnings after a rescan finds them readable again, show a warning when collaborators cannot be loaded, replace database error text in archive warnings with plain sentences, keep each song's notes on one line in Export Diagnostics, and hide every home folder path in diagnostics text.
- Keep the converter's mono output from dropping a channel: reducing stereo to mono now mixes both channels.
- Show the real disk error when a conversion cannot write its output, instead of "FFmpeg is required"; an FFmpeg that cannot run now offers Choose FFmpeg.
- Convert failed, skipped and canceled files again when they are added again, show "Canceled" instead of "Skipped" for canceled files, and show the handoff warning on verified files that have one.
- Skip unreadable files in a dropped folder and count them ("2 unreadable items skipped") instead of refusing the whole drop, convert sources with layouts such as quad or 5.0, shorten very long output names to fit the file system, and reject a 32-bit float file where 32-bit integer WAV is expected.
- Download playlists with 25 or more entries (they never downloaded before), name a playlist job after the playlist, and check a playlist link without reading every entry first.
- Make "MP4 (720p)" give 720p on YouTube and never more than 720p on other sites.
- Show "already exists" for files that are already downloaded, report a broken yt-dlp as a helper problem instead of "URL not supported", name jobs after the site when a link has no useful title, keep progress from jumping on a percent sign in a file name, and stop calling a yt-dlp of exactly the minimum age outdated.
- Keep the audio already recorded when writing a take fails part-way: the error card names the kept file, says it may be incomplete and offers Show Kept Take. An empty take is still removed.
- Show "Output Folder Not Allowed" with the plain reason when the recorder's output folder is inside a music archive, instead of a full-disk message.
- Count the recorder's timer and time limit from audio actually written, show the error of a failed stop at the time limit instead of "No active recording", and stop a recording that is stopped while it starts or while the audio route changes from starting anyway.
- Stop custom recording names from producing hidden files or doubled extensions (a name such as "Take.wav.mp3" now saves as "Take.wav"), meter interleaved audio correctly, and stop odd stored values from crashing the duration display or the time-limit setting.
- Explain in the macOS microphone prompt why it appears on audio interfaces and other output devices with inputs: nothing records the microphone, and previews play either way.
- Accept only readable audio files as stems, add a finished stem set to the Output Inbox all at once or not at all, and keep job folder and stem names within the file system's length limit for long titles.
- Show a plain cause when stem separation fails (the exit code and the Python error line, with home paths hidden) instead of the helper's raw output, show "Stem helper can't start" for an installed helper that does not run, wait for setup before YouTube to Stems starts, and start progress again at 0 after a model download.
- Follow a steady slower tempo in BPM Tapper instead of keeping the old BPM, clear the "BPM copied" badge, keep the unreadable-history message when a save fails, and stop an odd saved value from crashing the history.
- Show the full BPM line in Output Inbox rows ("119.7 BPM", "Analyzing…", "No tempo" when none is found), keep the list visible when a BPM cannot be saved (the row says "Not saved"), and offer Analyze BPM only for audio files that are there.
- Explain an Open at login switch that macOS holds for approval, with an Open Login Items button, instead of letting it snap back without a word.
- Move through every tool with the arrow keys in the sidebar, open the main window from the Dock menu even when no window is open, and stop ⌘F from refocusing archive search each time the main window reopens.
- Stop reporting "Up to date" after an update was dismissed, skipped or staged, keep the menu bar icon setting and helper paths as they were when saving them fails, open System Settings once instead of twice, size the first-run Music archive sheet to its content, draw no waveform bar as played before playback starts, stop a helper that closes its output early from keeping a processor core busy, and stop a finished job from coming back in the job status.
- Make the command-line tool print an error and exit with code 1 instead of crashing, and write Export Index files in one step so an interrupted export cannot leave a cut-off file.

## 1.7.3 - 2026-09-28

- Ask before quitting while a download (from the moment Download is pressed), stem separation, conversion, recording, helper install or Project Vault operation is running; on Stop and Quit, cancel it cleanly (a recording keeps its take) and wait up to 5 seconds for it to finish.
- Stop helper processes such as yt-dlp, FFmpeg and stem separation that are still running when the app quits, instead of leaving them behind.
- Re-check the Active project folder after the final verification before freeing space, and never follow symbolic links while hashing, so a file saved during a long verification is no longer removed without a copy.
- Stop the first Archive Now or backup copy of a freshly saved project from failing with "Project files changed while archiving" when nothing changed; macOS trimming unused disk space reserved for a new file no longer counts as a change.
- Resume every readable Project Vault record at launch and report the ones that cannot be read, instead of skipping all recovery when one record is damaged.
- Keep a song's saved title, notes and status when it is edited after a discarded rescan.
- Make Stop take effect while a large project is being hashed, report a stop during copy, verify or restore as a stop rather than a failure, and leave a stopped iCloud restore for Retry instead of reopening it at the next launch.
- Refuse to write Export Index, Export Diagnostics or a New Song folder into the Project Vault archive folder.
- Stop a recording and show the error as soon as writing to disk fails, instead of reporting it only after Stop.
- Report a song folder that cannot be listed as skipped instead of showing it with no project files, and leave it out of the archive the same way after a full or an automatic rescan, whatever the listing error.
- Open Stem Separation faster with a populated result history by loading offscreen result rows as they come into view, while preserving scrolling, file actions, and tab state.

## 1.7.2 - 2026-09-25

- Make Project Vault restore retries respect Emergency Stop, preserve Keep Local during interrupted recovery, and require verified durability before removing an Active copy.
- Stop cancelled and outdated archive scans from replacing newer results, keep automatic recovery scans from replacing active Vault progress, keep preview caches bounded, and improve project-version detection, exclusions, and search relevance.
- Save song notes and collaborator changes consistently across archives, preserve identity-review decisions, and refresh plug-in results and analytics when projects change.
- Keep Output Inbox updates atomic, preserve recordings when inbox handoff fails, normalize recording filenames, and reject invalid tempo taps.
- Keep recorder controls, recent outputs, and stem inputs usable in narrow windows, preserve converter preset alignment, and make inbox visibility controls reflect the selected state.
- Improve archive workflow copy and board scrolling, and strengthen release provenance checks and local-install recovery.

## 1.7.1 - 2026-09-24

- Make first-run helper installation a single guided step, keep downloads and conversions cancellable, and prevent cancelled helper installs from resetting a newer attempt.
- Keep recorder permission checks bounded and inaudible, preserve takes when capture is lost, and record the correct tap stream on output devices that also have inputs.
- Repair settings and song metadata without loosening Project Vault protections; keep archive roots read-only, including CLI exports, and recheck song folders against symlink changes during scans.
- Keep incomplete downloads out of the output folder, avoid false stalls during post-processing, and support the converter's 32-bit FFmpeg fallback.
- Improve mixdown key detection at 88.2 and 96 kHz, reject hidden song-draft names, and tighten path containment for stem outputs and diagnostics.

## 1.7.0 - 2026-09-22

- Choose how archiving treats the Active copy: Keep a verified copy, or Archive and free up space. Earlier copy-only choices stay copy-only and never gain removal.
- Background Vault scheduling stays off unless opted in separately from manual archiving.
- Song completion offers Archive and free up space (only when permitted), Keep a verified copy, Keep on this Mac, or Keep Status, with the same manual confirmation on board and in detail.
- Delayed retries stay copy-only; a verified archive with persisted recovery evidence offers Ready to free space under a fresh confirmation.
- In-flight, pending, and failed copies stay on the board; archived-only songs stay hidden until shown again.
- Restoring keeps the song's workflow stage, pins Keep Local before copying or opening, and offers Resume work to move explicitly to Prod.
- Recovery copies export the full catalog and settings through an online database backup, import as a fresh isolated library with automation disabled and paused, and remain available while Vault is off. External samples and plug-ins are not collected.
- A disabled Vault hides its configured roots from the board until re-enabled; a paused restore stays paused until explicitly unpaused.
- Edit ▸ Undo and Redo (Command-Z) now undo board status and song-note changes while the archive is shown, and never reach those changes from another tool. Running archive copies show their live stage (Copying, Verifying, Waiting for upload), and automatic Done copies skip projects kept on this Mac without reporting them as needing attention.
- Opening the WAV Converter no longer keeps the app busy in the background: since 1.5.0 it could hold a processor core at full load until the app quit, including after relaunching into the converter.
- Dragging a file out of the Output Inbox or the WAV Converter keeps its filename; Finder previously saved it under a generic name such as "Waveform audio.wav".

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
