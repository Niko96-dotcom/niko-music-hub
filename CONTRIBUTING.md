# Contributing

Thanks for taking a look at Niko Music Hub.

## Local Setup

```bash
git clone https://github.com/Niko96-dotcom/niko-music-hub.git
cd niko-music-hub
./script/ci.sh
```

## Development Rules

| Rule | Why |
| --- | --- |
| Keep the app native Swift/SwiftUI/AppKit. | The product should stay lightweight and macOS-native. |
| Keep archive roots read-only. | Users' real Cubase/music files must remain untouched. |
| Use generated fixtures for tests. | Public tests should not depend on private projects or local media. |
| Keep feature modules isolated. | Archive, tapper, converter, recorder, downloader, and inbox behavior should remain easy to reason about. |
| Run local gates before proposing changes. | GitHub Actions are not the release source of truth right now. |

## Verification

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
./script/build_and_run.sh --verify
```

Recorder hardware checks may need manual validation on a Mac with supported CoreAudio capture and granted macOS privacy permission.
