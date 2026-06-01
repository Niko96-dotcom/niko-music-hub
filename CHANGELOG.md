# Changelog

## v0.1.0 - 2026-06-01

### Added

- Native macOS SwiftUI app target `NikoMusicHub`.
- Cubase archive browser with root selection, scan, search, preview ranking, CPR version list, diagnostics, and dry-run latest CPR open.
- Public generated Cubase archive fixtures and fixture-first test coverage.
- BPM tapper, audio converter, audio recorder, downloader, and output inbox modules.
- Local verification scripts: `script/ci.sh`, `script/e2e_user_smoke.sh`, and `script/build_and_run.sh --verify`.
- GitHub landing page under `docs/index.html`.

### Safety

- Archive scanning is read-only toward selected music roots.
- Generated outputs are written to the selected output folder.
- No real Cubase projects or private music files are included in fixtures.

### Known Limits

- Signing and notarization are not included.
- GitHub Actions are not configured.
- Host-only CoreAudio recorder tests require local hardware and macOS privacy permission.
