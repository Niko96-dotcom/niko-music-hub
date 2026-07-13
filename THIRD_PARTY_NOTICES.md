# Third-Party Notices

Niko Music Hub is built with the Swift toolchain and links Apple platform frameworks and the macOS system SQLite library. Those system components are not redistributed in the source-sale archive and remain governed by Apple and toolchain terms.

The application can invoke these separately installed, user-supplied helpers:

| Helper | Purpose | Bundled? | License responsibility |
|---|---|---:|---|
| FFmpeg | Optional media conversion/probing | No | The installer/operator must review the license and build configuration of the installed FFmpeg distribution. |
| yt-dlp | Optional media download | No | The installer/operator must review the license distributed with the installed yt-dlp version. |
| demucs-mlx | Optional local stem separation | No | The installer/operator must review the license distributed with the installed demucs-mlx version and its models. |

The internal engineering repository also vendors Ultimate De-Slop under the MIT License. That development-only tooling is deliberately excluded from the source-sale export, so its files and license do not become part of the buyer package.

No third-party binary, model, media file, package dependency, or Python runtime is embedded in the Niko Music Hub product or source-sale export by the project’s build manifest.
