# Stem Separation User Guide

Niko Music Hub can split a stereo audio file into separate stems (vocals, drums, bass, other, and optionally guitar and piano) using a local Demucs model through `demucs-mlx`.

## Prerequisites

Install `demucs-mlx` in a Python environment. The app does not bundle Python or the model.

```bash
pip install demucs-mlx
```

After installation, make sure the `demucs-mlx` executable is on your `PATH`, or configure its full path in **Settings**.

The first time you run a preset, `demucs-mlx` downloads and converts the model. This can take several minutes depending on your connection. The app shows download progress in the status area.

## Opening the tool

1. Open Niko Music Hub.
2. Select **Stems** in the sidebar.

## Running separation

1. Drop an audio file onto the drop area, or click **Choose File...** to pick one. Supported formats include WAV, AIFF, MP3, M4A, and FLAC.
2. Choose a preset:
   - **Fast 4-stem** — uses `htdemucs`; fastest, good quality.
   - **Best 4-stem** — uses `htdemucs_ft`; best standard Demucs quality, slower.
   - **Experimental 6-stem** — uses `htdemucs_6s`; also separates guitar and piano. Quality of the extra stems may vary.
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
| "Executable not found" | `demucs-mlx` is not on `PATH` | Install it, or set the executable path in Settings |
| "Model cache missing" | First run has not downloaded the model | Run any preset; the model downloads automatically |
| "Backend unavailable" | The version check failed | Check that `demucs-mlx --version` works in Terminal |
| No stems after success | Output scanner could not identify files | Check the output folder for files named with known stem roles |
| Cancel did nothing | Job already finished or failed | Check the status message |

## Privacy note

All processing happens locally on your Mac. No audio leaves your machine.
