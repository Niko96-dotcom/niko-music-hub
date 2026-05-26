# Niko Music Hub — Agent Rules

## Mission

Build **Niko Music Hub**: one native macOS SwiftUI app combining the tested OutsideCubaseHub tools with a new Cubase archive browser.

Use the existing Swift app as the seed. Do not start blank. Do not embed Electron/React/TypeScript/Python runtime code into the product. Port behavior into Swift modules.

## Product boundaries

- Native macOS app, Swift 6.x, SwiftUI + AppKit interop where useful.
- Local-first and read-only toward real music archives by default.
- Never rename, move, delete, or rewrite real Cubase/music files.
- Fixture-first tests are mandatory.
- User-style E2E is mandatory before calling v0.1 done.
- GitHub Actions are not required; local gates are the truth because billing is annoying.

## Architecture target

- `NikoMusicCore`: pure Swift domain/scanning/search/opening safety. No SwiftUI, no AppKit UI.
- `AppCore`: shared tool registry, settings, jobs, output inbox, diagnostics.
- `FeatureArchiveBrowser`: SwiftUI feature registered through the same `ToolFeature` boundary as the existing tools.
- Existing outside-Cubase features stay modular: BPM tapper, audio converter, audio recorder, downloader, output inbox.
- App target becomes `NikoMusicHub` and app name becomes `Niko Music Hub`.

## Source/reference inputs

- Main plan: `docs/niko-music-hub-composer-execution-plan.md`
- Seed app source: current repo, copied from `/Users/niko/Documents/OutSideCubaseHub`
- Cubase reference docs: `docs/reference/cubase-file-orga/`
- SwiftUI style reference: `/Users/nikolaymohr/src/automation-health`

## Composer/Pi workflow

Niko explicitly wants product implementation by Composer 2.5 via Pi Agent SDK, sequentially:

1. Planner: docs/task queue only.
2. Critic: docs/task queue only.
3. Executor: product code, tests, scripts, green commits.
4. Reviewer: final review, blocker fixes only.

No Hermes worker fan-out. No parallel coding agents. One checkout, one Composer process at a time.

## Isolation

Do not touch:

- `/Users/nikolaymohr/locus`
- `/Users/nikolaymohr/.hermes/worktrees/locus-*`
- `/Users/nikolaymohr/.hermes/workers/locus-*`

Do not set or depend on `LOCUS_*` environment variables.

MacBook is read-only/reference unless a task explicitly says copy source/reference files. Do not modify MacBook projects in place.

## Local development (Mac)

Canonical working copy:

```text
/Users/niko/Documents/Niko-Music-Hub
```

Install or refresh: `./script/bootstrap_documents_mac.sh` (see `docs/local-development.md`). Cloud/Linux sandboxes may edit source but cannot run `swift test`; validate on the Mac checkout before merge.

## Local gates

Run on macOS in the Documents checkout:

```bash
./script/ci.sh
./script/e2e_user_smoke.sh
```

`./script/ci.sh` skips host-only CoreAudio recording tests that require a usable system-audio capture device. Those tests are still part of the source suite; they are just not a reliable always-on-Mac gate.

## Git rules

- Keep commits coherent.
- Commit only green local states during execution.
- Do not push unless the prompt or user explicitly asks for push.
- Do not commit `.ai/runs/`, build output, DerivedData, `.DS_Store`, or personal scan logs.
