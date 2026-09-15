# Cubase, Ableton Live, and Project Vault restore

## Song folders

Choose an archive root containing your song folders. Each immediate child folder is one song. The scanner finds Cubase `.cpr` and Ableton Live `.als` files recursively inside it, including DAW-specific subfolders. Separate folders remain separate songs even if their project files are identical. Vault cannot reuse a transfer to remove a different Active folder, or reuse a generation from a previously configured Vault root.

```text
Music/                         ← choose this as the archive root
  Shared Song/                 ← one song card
    Shared Song.cpr
    Live Project/
      Shared Song.als
      Samples/
  Ableton Song/                ← another song card
    Ableton Song.als
    Samples/
  Cubase Song/                 ← another song card
    Cubase Song.cpr
    Audio/
```

Use Rescan after adding existing Ableton projects to a previously scanned library. Subsequent filesystem updates use the same incremental scan flow as Cubase.

The main project defaults to the newest modification date across both formats. In song details, expand **Project files** to see **Project versions**. Each row identifies its DAW; use the row's **… → Open in Cubase / Open in Ableton Live** to open that version, or **Set Main** to make it the default. Main selection, hidden versions, titles, notes, collaborators, workflow status, search, and previews belong to the song, independent of its DAW. Main selection is stored in the hub and survives rescanning without changing project files.

Ableton's automatic `Backup` sets and `Ableton Project Info` files are excluded from working-project selection. They are still included when Vault copies the entire song folder. Exports can be previewed; imported, recorded, and processed samples receive a lower source-sample ranking. The hub does not render an ALS or CPR into a preview: export audio from the DAW for playback in the hub.

Open uses macOS's file association, so associate `.als` with Ableton Live and `.cpr` with Cubase. If macOS refuses to open a file, the hub reports the failure. Plug-in names are read on demand from supported Live XML fields; malformed or unsupported metadata does not prevent browsing or opening the set.

## Song identity and previews

The folder groups the project's files and remains its filesystem identity. The displayed song title comes from the selected full-song delivery when available, including exports without an artist prefix (`New Song DEMO V2.wav` becomes `New Song`) and numeric titles (`404 DEMO V1.wav` becomes `404`). Version, production and writer-credit suffixes are removed; words inside the title are retained. A virtual title in Song info remains the explicit user override.

Automatic preview selection checks full-song suitability before scores, versions or modification dates. Stems, references, short clips and technical exports such as `for ableton` or `for mastering` cannot outrank a usable full-song mix. Among usable full songs, exports in the song root or Mixdown folder take precedence over imported audio in project subfolders. A finished song inside Cubase's Audio folder remains eligible when no such export exists. The same core rules run on fresh scans and cached automatic selections; manual preview choices stay intact. Vault refreshes the canonical title when archiving the active song, including when reusing an existing verified generation, without changing the ProjectID, folder or music files.

## Archive in the UI

**Archive Now** verifies the Vault generation and current project, checks that the DAW and project files are closed, then removes the Active copy. The song leaves the normal board and becomes a **Get Local & Open** target under **Show archived projects**. A restored, unchanged song can reuse its verified generation when archived again.

**Create Backup Copy** verifies a Vault copy and keeps the song in Active Projects. Use this when you want another copy without removing the local project.

Existing archive folders explicitly linked to a catalog identity also appear under **Show archived projects**. Their details report whether files are local, online-only, or downloading, and offer **Show in Finder**. Linking preserves the project ID, original evidence, historical locations and user metadata. It does not create a verified Vault generation or enable **Get Local & Open**; that action requires a managed, verified backup. File availability comes from the files inside the folder, since a locally present Dropbox folder may contain online-only audio and project files.

Manual archiving requires Project Vault enabled, independent backup confirmation, Keep Local off, and Emergency Stop off. It can run after a save without waiting for the automatic inactivity window. Private beta limits automatic archiving to copies; it does not convert an explicit Archive Now request into a copy-only success. If removal is blocked, the app reports the reason and keeps the Active project.

## Multiple requests

Archive, backup, restore, and retry requests for different songs share one queue and run in the order requested. Repeated clicks for a song already running or waiting are ignored. Song details show the running action or queue position and let you cancel a waiting request. Safety settings and configured folders are checked again before execution. A failed request is marked for attention, and the next song continues.

Waiting requests remain queued while Niko Music Hub is open; they are not saved across quitting the app. If requests are running or waiting, Quit asks you to keep Music Hub open or explicitly cancel waiting requests and quit. Transfers that already started retain durable recovery records.

## Restore in the UI

1. In **Settings → Project Vault**, configure **Active Projects** (your working folder) and **Archive / Vault**, and enable Project Vault.
2. In the archive browser sidebar, click the archive-box control **Show archived projects**, also available in the sidebar menu. Verified archive-only songs appear with their existing workflow status and an **Archived** label.
3. Select the song and click **Restore & Open**. The small **Get** action on its card starts the same operation.
4. The hub makes the verified archive generation available locally if needed, copies the whole song into Active Projects, verifies it, and saves the restored location before opening its newest working project in the matching DAW. The archive copy stays intact. An occupied destination is never overwritten.
5. After restore, the song is active again. Use **Keep Local** if you want automatic archiving to leave that active copy on the Mac.

Restore opens the newest working project in the restored folder. For mixed songs, use **Project versions** after restoration to open or select a different version. **Keep Local** alone does not download an archived song. **Test Restore** in Settings runs a disposable rehearsal; it does not restore one of your songs. If an online-only generation requires manual download, the UI directs you to its exact Finder location and **Retry Get Local**.

## Recover an interrupted archive

If the app stops while removing an Active copy or evicting a provider cache, launch recovery pauses that transfer for review. Song details offer **Recover Verified Project**. This downloads the archive if needed, verifies its complete manifest, preserves any surviving Active folder under `.niko-recovery` inside Active Projects, and restores a complete verified copy. **Reveal Preserved Files** opens the preserved folder so you can compare any newer work. Recovery never merges or deletes those surviving files. It requires available configured folders, sufficient free space, closed DAWs/project files, and Emergency Stop off. A corrupt archive or unsafe path stops recovery and retains existing copies.

## Names in provider-backed archives

Project Vault preserves original project paths when a storage provider cannot accept names such as a trailing-space folder or Finder's `Icon` file with a carriage return. New transfers use a versioned archive representation for those names. Restore recreates the original names and verifies the restored content against the original manifest.

For a failed legacy transfer, Retry can rebuild that representation only after the complete Active source matches the saved content hashes. It retains the previous staging tree for recovery. Existing literal-path archives remain supported. Older app builds cannot restore the new representation and fail verification safely; use the current build for those generations.

## Independent backup and catalog recovery

The independent-backup checkbox records your confirmation; Music Hub does not create or verify that backup for you. Back up the complete song folders and Vault generations, plus the Hub catalog and settings. Archive manifests, transfer history and song metadata are stored in `~/Library/Application Support/Niko Music Hub/archive-index.sqlite`. With Music Hub quit, back up its application-support folder and settings together; a live SQLite copy requires a consistent SQLite backup, including committed WAL changes, rather than copying just the database file.

For catalog loss, quit Music Hub, preserve the damaged application-support folder, and restore a known-good backup. Reconnect or reselect the original Active and Vault folders, then verify a disposable restore before normal use. Do not delete a damaged catalog to dismiss an error: without the catalog, existing generation folders alone do not reconstruct verified Vault history. A replacement Mac also needs DAWs, plug-ins and their licenses, external sample libraries, and newly granted folder access. A same-Mac recovery rehearsal does not prove replacement-Mac compatibility.

## Ableton portability

Before archiving a Live project, use **File → Collect All and Save** in Live to put externally referenced samples into its project folder. Vault copies and verifies the song folder's contents; it does not rewrite the Live Set or gather external dependencies. Third-party plug-ins still need to be installed separately. Vault's existing activity gate also postpones transfers while Ableton Live is running.

References: [Ableton project saving](https://help.ableton.com/hc/en-us/articles/115000915804-Saving-Projects), [Collect All and Save](https://help.ableton.com/hc/en-us/articles/209775645-Collect-All-and-Save), [Backup Sets](https://help.ableton.com/hc/en-us/articles/360000377870-Backup-Sets).

## Compatibility and verification

The shared scanner/detector are `MusicArchiveScanner` and `ProjectVersionDetector`; the original Cubase names remain source-compatible aliases. Persisted CPR-named metadata keys, sort identifiers, Vault phase names, and identity-evidence fields retain their existing encoding and now carry either project format. No catalog reset or migration is required.

Fixture coverage includes mixed and separate songs, loose sets and incremental rescanning, manual main selection, safe opening, templates, preview ranking, bounded gzip/XML plug-in extraction, and full-folder Vault restore. The app's E2E smoke includes a mixed-DAW flow with dry-run opening and an unchanged fixture archive. This does not certify playback in a real Cubase or Ableton installation.
