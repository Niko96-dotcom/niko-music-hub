# Install Niko Music Hub

Niko Music Hub supports Apple silicon (`arm64`) Macs running macOS 14.2 or newer. Intel and universal builds are not supported release targets.

Download the DMG and matching `.sha256` file from the GitHub Release.

Verify the checksum from the download folder:

```bash
shasum -a 256 -c NikoMusicHub-<version>.dmg.sha256
```

Open the DMG and drag `NikoMusicHub.app` into `/Applications`.

To verify an installed release directly:

```bash
./script/verify-installed-release.sh /Applications/NikoMusicHub.app
```

## First launch

The **Set Up Niko Music Hub** window opens once:

- **Download & Convert** installs yt-dlp and FFmpeg (about 100 MB).
- **Stem Separation** installs demucs-mlx and prepares its model (about 1.2 GB; takes a few minutes).
- **Music Archive** picks your Cubase or Ableton projects folder.

Click **Install All** or install each row on its own. Everything is optional; close the window with **Later** and reopen it any time from **Help → Set Up Helper Tools…**. The tools go into `~/Library/Application Support/Niko Music Hub/Tools`; nothing is installed system-wide and no password is needed. If you already have Homebrew copies, the app uses those as well.

Niko Music Hub checks for updates on its own once a day and can install them for you. Use **Niko Music Hub ▸ Check for Updates…** to check immediately, or turn automatic checks off under **Settings ▸ Updates**. Updates are downloaded from the signed release feed and their signature is verified before anything is unpacked.

You can also upgrade manually by replacing `/Applications/NikoMusicHub.app` with the app from the newer DMG.

Uninstall by quitting Niko Music Hub and removing `/Applications/NikoMusicHub.app`. App metadata is stored in `~/Library/Application Support/Niko Music Hub/`; remove that folder only if you intentionally want to clear local app state. It also holds the downloaded helper tools (`Tools/`). Stem models live in `~/.cache/demucs-mlx`.
