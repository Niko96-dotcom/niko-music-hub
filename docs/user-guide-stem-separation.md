# Stem Separation User Guide

Niko Music Hub can split a stereo audio file into separate stems (vocals, drums, bass, other, and optionally guitar and piano) using a local Demucs model through `demucs-mlx`.

## Prerequisites

Stem Separation needs `demucs-mlx`. Install it from the app: **Help → Set Up Helper Tools…**, then **Install** on the **Stem Separation** row. The app downloads a private Python and `demucs-mlx` into `~/Library/Application Support/Niko Music Hub/Tools` and prepares the default model (about 1.2 GB in total, a few minutes). No Terminal, Homebrew, or Python install is needed.

If you already installed `demucs-mlx` yourself (for example with `uv tool install demucs-mlx` into `~/.local/bin`), the app finds it automatically, or you can set its path in **Settings → Helpers**.

## Opening the tool

1. Open Niko Music Hub.
2. Select **Stems** in the sidebar.

## Running separation

1. Drop an audio file onto the drop area, or click **Choose File...** to pick one. Supported formats include WAV, AIFF, MP3, M4A, and FLAC.
2. Choose a preset:
   - **Fast 4-stem** — uses `htdemucs`; fastest, good quality. The first run downloads and prepares this model.
   - **Best 4-stem** — uses `htdemucs_ft`; best standard Demucs quality, slower. Setup prepares this model already.

   A 6-stem preset (guitar and piano) exists in the code but is hidden in this release.
3. Choose the output folder. The default is `~/Music/Niko Music Hub/Inbox`.
4. Click **Start Separation**.

The progress bar and status label show what the backend is doing. You can click **Cancel** to stop the current job. Already-written stem files remain in the output folder.

## Working with results

When separation finishes, the generated stems appear in the results list. For each stem you can:

- Click **Reveal** to open the enclosing folder in Finder.
- Drag the row directly into a Cubase track or folder.

Stems are also added to the global Output Inbox, so you can find them again from any tool.

## Troubleshooting

| Problem | Likely cause | Fix |
|---------|--------------|-----|
| "demucs-mlx is not installed" | The helper is missing | Click **Install Tools** on the card, or use **Help → Set Up Helper Tools…** |
| "demucs-mlx could not start" | The helper is broken or incomplete | Install it again from the setup window; the message shows the helper's own error |
| No stems after success | Output scanner could not identify files | Check the output folder for files named with known stem roles |
| Cancel did nothing | Job already finished or failed | Check the status message |

## Privacy note

All processing happens locally on your Mac. No audio leaves your machine.
