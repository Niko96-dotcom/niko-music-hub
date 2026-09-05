# Cubase, Ableton Live, and Project Vault restore

## Song folders

Choose an archive root containing your song folders. Each immediate child folder is one song. The scanner finds Cubase `.cpr` and Ableton Live `.als` files recursively inside it, including DAW-specific subfolders. Separate folders remain separate songs even if their project filenames match.

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

Manual archiving requires Project Vault enabled, independent backup confirmation, Keep Local off, and Emergency Stop off. It can run after a save without waiting for the automatic inactivity window. Private beta limits automatic archiving to copies; it does not convert an explicit Archive Now request into a copy-only success. If removal is blocked, the app reports the reason and keeps the Active project.

## Restore in the UI

1. In **Settings → Project Vault**, configure **Active Projects** (your working folder) and **Archive / Vault**, and enable Project Vault.
2. In the archive browser sidebar, click the archive-box control **Show archived projects**, also available in the sidebar menu. Verified archive-only songs appear with their existing workflow status and an **Archived** label.
3. Select the song and click **Restore & Open**. The small **Get** action on its card starts the same operation.
4. The hub makes the verified archive generation available locally if needed, copies the whole song into Active Projects, verifies it, and saves the restored location before opening its newest working project in the matching DAW. The archive copy stays intact. An occupied destination is never overwritten.
5. After restore, the song is active again. Use **Keep Local** if you want automatic archiving to leave that active copy on the Mac.

Restore opens the newest working project in the restored folder. For mixed songs, use **Project versions** after restoration to open or select a different version. **Keep Local** alone does not download an archived song. **Test Restore** in Settings runs a disposable rehearsal; it does not restore one of your songs. If an online-only generation requires manual download, the UI directs you to its exact Finder location and **Retry Get Local**.

## Ableton portability

Before archiving a Live project, use **File → Collect All and Save** in Live to put externally referenced samples into its project folder. Vault copies and verifies the song folder's contents; it does not rewrite the Live Set or gather external dependencies. Third-party plug-ins still need to be installed separately. Vault's existing activity gate also postpones transfers while Ableton Live is running.

References: [Ableton project saving](https://help.ableton.com/hc/en-us/articles/115000915804-Saving-Projects), [Collect All and Save](https://help.ableton.com/hc/en-us/articles/209775645-Collect-All-and-Save), [Backup Sets](https://help.ableton.com/hc/en-us/articles/360000377870-Backup-Sets).

## Compatibility and verification

The shared scanner/detector are `MusicArchiveScanner` and `ProjectVersionDetector`; the original Cubase names remain source-compatible aliases. Persisted CPR-named metadata keys, sort identifiers, Vault phase names, and identity-evidence fields retain their existing encoding and now carry either project format. No catalog reset or migration is required.

Fixture coverage includes mixed and separate songs, loose sets and incremental rescanning, manual main selection, safe opening, templates, preview ranking, bounded gzip/XML plug-in extraction, and full-folder Vault restore. The app's E2E smoke includes a mixed-DAW flow with dry-run opening and an unchanged fixture archive. This does not certify playback in a real Cubase or Ableton installation.
