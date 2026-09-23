# Third-Party Notices

Niko Music Hub is built with the Swift toolchain and links Apple platform frameworks and the macOS system SQLite library. Those system components are not redistributed in the source-sale archive and remain governed by Apple and toolchain terms.

The app bundles [Sparkle](https://github.com/sparkle-project/Sparkle) for signed in-app updates. `Package.swift` pins version 2.9.6, and `Package.resolved` records its exact revision. Sparkle is distributed under the MIT License and includes additional third-party notices in its [upstream LICENSE](https://github.com/sparkle-project/Sparkle/blob/2.9.6/LICENSE). The build copies this complete file from the resolved package artifact into `NikoMusicHub.app/Contents/Resources/Sparkle-LICENSE.txt` before signing. The source export includes the package declaration and lockfile; Swift Package Manager obtains the dependency during a build.

The application can invoke these separately installed helpers. They are never shipped inside the app. When the user clicks **Install** in the setup window, the app downloads them at that moment from the upstream publishers listed below, verifies each download against the SHA-256 checksum the publisher provides, and stores them in `~/Library/Application Support/Niko Music Hub/Tools`:

- yt-dlp: `yt-dlp_macos` from the yt-dlp GitHub releases (Unlicense).
- FFmpeg and ffprobe: macOS arm64 release builds from ffmpeg.martin-riedl.de (signed by their publisher; FFmpeg is LGPL/GPL depending on build configuration).
- demucs-mlx: installed from PyPI by `uv` (Astral, MIT/Apache-2.0), which also downloads a standalone CPython build (PSF License). demucs-mlx is MIT; its model weights come from the official Demucs release (MIT).


| Helper | Purpose | Bundled? | License responsibility |
|---|---|---:|---|
| FFmpeg | Optional media conversion/probing | No | The installer/operator must review the license and build configuration of the installed FFmpeg distribution. |
| yt-dlp | Optional media download | No | The installer/operator must review the license distributed with the installed yt-dlp version. |
| demucs-mlx | Optional local stem separation | No | The installer/operator must review the license distributed with the installed demucs-mlx version and its models. |

The internal engineering repository also vendors Ultimate De-Slop under the MIT License. That development-only tooling is deliberately excluded from the source-sale export, so its files and license do not become part of the buyer package.

The build embeds the Sparkle framework and its updater helpers. It does not embed FFmpeg, yt-dlp, demucs-mlx, their models, or a Python runtime; those are only downloaded on the user's request as described above.
