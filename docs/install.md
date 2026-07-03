# Install Niko Music Hub

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

Upgrade by replacing `/Applications/NikoMusicHub.app` with the app from the newer DMG.

Uninstall by quitting Niko Music Hub and removing `/Applications/NikoMusicHub.app`. App metadata is stored in `~/Library/Application Support/Niko Music Hub/`; remove that folder only if you intentionally want to clear local app state.
