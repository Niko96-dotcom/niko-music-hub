You are Composer 2.5 running via Pi Agent SDK. You are the PLANNER for Niko Music Hub.

Repo: `/Users/niko/Documents/Niko-Music-Hub`
Mission: turn the existing Swift `OutsideCubaseHub` seed plus the Cubase archive browser spec into one clean native SwiftUI app called **Niko Music Hub**.

Hard rules:
- Full Swift/SwiftUI product. No Electron runtime, no React, no TypeScript in product code.
- Use the copied OutsideCubaseHub source as the Swift seed; preserve existing outside-Cubase feature modules and tests.
- Reimplement Cubase archive browsing in Swift from spec/behavior, not by embedding Electron code.
- No Hermes workers, no parallel agents, no GitHub Actions requirement.
- No Locus interaction: do not touch `/Users/nikolaymohr/locus`, `/Users/nikolaymohr/.hermes/worktrees/locus-*`, or `/Users/nikolaymohr/.hermes/workers/locus-*`.
- Never rename, move, delete, or rewrite real music/archive files.
- Fixture-first tests and user-style E2E are mandatory.
- MacBook is read-only/reference; do not modify MacBook source projects.

Inspect first:
- `AGENTS.md`
- `docs/niko-music-hub-composer-execution-plan.md`
- `Package.swift`
- `Sources/AppCore/ToolRegistry.swift` or the actual ToolRegistry path if different
- `Sources/OutsideCubaseHub/AppComposition.swift` or the actual composition path if different
- `/Users/nikolaymohr/src/automation-health/Package.swift`
- `/Users/nikolaymohr/src/automation-health/Sources/AutomationHealth/App/AutomationHealthApp.swift`
- `docs/reference/cubase-file-orga/SPEC.md`
- `docs/reference/cubase-file-orga/DESIGN_SYSTEM.md`
- `docs/reference/cubase-file-orga/PROJECT.md`

Output only docs and task queue:
- `docs/source-inventory.md`
- `docs/product-scope.md`
- `docs/architecture.md`
- `.ai/tasks/v0.1-task-queue.json`

Task queue requirements:
- small vertical slices;
- exact files/modules likely touched;
- tests per slice;
- fixture E2E plan;
- real archive read-only smoke plan;
- explicit non-goals and safety boundaries.

Do not write product code yet. Do not rename package/app yet. End with a concise summary of files changed and the recommended executor order.
