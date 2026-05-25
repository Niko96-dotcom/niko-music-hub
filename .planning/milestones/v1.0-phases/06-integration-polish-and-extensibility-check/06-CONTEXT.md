# Phase 6: Integration Polish and Extensibility Check - Context

**Gathered:** 2026-05-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 6 makes Outside Cubase Hub feel like one coherent production bench rather than several unrelated panels. It establishes consistent keyboard shortcuts, standardized error language with clear recovery paths, cross-tool visual consistency, and verifies the architecture still welcomes new features through the registry with minimal isolated code.

This phase does not add new tools, change existing tool behavior, add new file formats, or modify the job runner or output inbox contracts.
</domain>

<decisions>
## Implementation Decisions

### 06-01: Error Language and Recovery

#### Error Taxonomy
All errors in the app fall into one of four categories. Each category has a consistent label style, structural format, and recovery pattern.

| Category | Label Pattern | Icon Pattern | Example |
|----------|--------------|--------------|---------|
| Permission | "Permission Required" / "Recording Restricted" | `lock.shield` / `exclamationmark.shield` | Recorder mic access |
| Helper Tool | "[Tool] Missing / Error" | `tool.badge.xmark` | FFmpeg/yt-dlp not found |
| Conversion/File | "Could Not [Verb]" / "[Noun] Failed" | `waveform.badge.xmark` / `externaldrive.badge.xmark` | File write, verification |
| Input/URL | "Invalid [Noun]" / "[Noun] Not Supported" | `xmark.circle` | Bad URL, unsupported type |

#### Standard Error Card Format
Every error card follows this structure:
1. **Label** (14pt semibold, color per severity) — what went wrong
2. **Body text** (12pt, secondary) — what it means in plain language
3. **Recovery section** (12pt) — one or more labeled buttons, never raw error dumps

Example:
```
Label: "Could Not Save Recording"
Icon:  externaldrive.badge.xmark
Body:  "Check available disk space. The output folder may be full or on a read-only volume."
Buttons: [ "Check Disk Space" (bordered) ] [ "Retry" (borderedProminent) ]
```

#### Existing Error Messages to Update
- BPM save failure: `"Could not save this BPM. Check local app storage, then try Save BPM again."` → `"Could Not Save BPM"` with card treatment and direct button to System Settings (standard macOS app storage location).
- Downloader yt-dlp missing: The inline hint button `DownloaderCopy.missingYtDlp` should use the standard card format with "Open Terminal" and "Retry" actions.
- Converter: Status text in row is not an error card; keep as inline colored text.

#### Recovery Action Patterns
- **Permission errors**: Always include "Open System Settings" + "Try Again" (or equivalent primary action).
- **Helper tool missing**: Include "Choose [Tool]..." button that opens a file picker for the executable path, plus "Check Installation" link.
- **File write errors**: Include "Reveal in Finder" to open the output folder, then "Retry".
- **API/driver errors**: Include "Retry" as the primary action.
- **Verification failures**: Include "Retry" with note that the file was discarded.

#### the agent's Discretion
Exact error card layout and color choices are flexible if they match the format above. The key constraint is consistency across features — same label/icon/body/button structure everywhere.

---

### 06-02: Keyboard Shortcuts and Menu Polish

#### Shortcut Strategy
macOS provides standard shortcuts automatically for menu items (`Cmd+,` for Settings, `Cmd+Q` for Quit, `Cmd+H` for Hide). Feature-specific shortcuts are **context-sensitive** — they only apply when the corresponding tool view is active and focused.

| Tool | Shortcut | Action | Context |
|------|----------|--------|---------|
| BPM Tapper | `Space` | Tap (when tap surface focused) | Already implemented (onKeyPress) |
| BPM Tapper | `Escape` | Reset taps | Already implemented |
| BPM Tapper | `Cmd+C` | Copy displayed BPM | When BPM is showing |
| BPM Tapper | `Cmd+S` | Save displayed BPM | When BPM is showing |
| Audio Converter | `Cmd+Shift+V` | Start conversion | When files are queued and converter focused |
| Audio Converter | `Escape` | Cancel/clear conversion | When converting |
| Audio Recorder | `Space` | Start/stop recording | When recorder is focused — already implemented |
| Audio Recorder | `Escape` | Cancel recording | When recording |
| Downloader | `Cmd+Enter` | Start download | When URL is entered and downloader focused |
| Downloader | `Escape` | Clear input | When URL field has content |
| All tools | `Cmd+,` | Open settings | Global (menu-driven) |
| All tools | `Cmd+Shift+O` | Reveal last output in Finder | When output exists |

#### Global vs. Context-Sensitive
- **Global shortcuts** (Cmd+, Cmd+Q, etc.) are handled by the macOS menu system automatically.
- **Context-sensitive shortcuts** use SwiftUI's `.focused()` + `.onKeyPress()` pattern already established in BPMTapperView and AudioRecorderView.
- Shortcuts **do not** override standard macOS behavior (Tab, Arrow keys, etc.).

#### Menu Polish
The app's menu bar should include:
- **Outside Cubase Hub** menu: About, Hide, Quit
- **File** menu: Settings (Cmd+,), Close Window
- **Edit** menu: standard (Undo, Cut, Copy, Paste, Select All)
- **Window** menu: standard (Minimize, Zoom, etc.)
- **Help** menu: "Outside Cubase Hub Help" (links to a local help page or shows a brief overlay)

The app should NOT have a custom toolbar with extra buttons — keyboard shortcuts and the compact sidebar navigation are the primary interaction model.

#### Menu Structure for Jobs
When a job is running (conversion, recording, download), the Window menu should show the active tool name with an indicator. The primary feedback for active jobs remains in the tool view itself.

#### the agent's Discretion
The exact menu structure and keyboard shortcut bindings are flexible as long as:
- Standard macOS conventions are respected
- Feature shortcuts only fire when their tool is active/focused
- No shortcut conflicts with system or other feature shortcuts

---

### 06-03: Cross-Tool Consistency Pass

#### Shared Visual Patterns to Align

**Header block** (every tool view):
```
VStack(alignment: .leading, spacing: 8) {
    Label("[Tool Name]", systemImage: "[icon]")
        .font(.system(size: 16, weight: .semibold))
    Text(statusText)
        .font(.system(size: 13))
        .foregroundStyle(statusColor) // .secondary, .green, .orange, .red
        .lineLimit(2)
}
.frame(maxWidth: toolMaxWidth, alignment: .leading)
```

**Status colors** — consistent across all tools:
| Meaning | Color |
|---------|-------|
| Idle / Ready | `.secondary` |
| Running / Active | `.green` or `.accentColor` |
| Warning / Needs Attention | `.orange` |
| Error / Failed | `.red` |

**Output row/card pattern** (for conversion, recording, download results):
- Status dot (8pt circle, status color)
- Source filename (13pt semibold)
- Output name or target (12pt, secondary)
- Status text (12pt, status color)
- Inline progress bar (when running)
- Recovery action button(s) right-aligned
- Reveal/drag hint when output is ready

**Action button ordering**:
- Primary action: `.borderedProminent`
- Secondary actions: `.bordered`
- Destructive: `.bordered` + `.foregroundStyle(.red)`

#### Current State vs. Target
- **BPM Tapper**: ✓ Already consistent — compact header, tap surface, action row, history.
- **Converter**: ✓ Already mostly consistent — header, intake surface, preset strip, action row, batch rows with status dots.
- **Recorder**: ✓ Already mostly consistent — header, meter, time, control, settings, error cards.
- **Downloader**: ✓ Already mostly consistent — header, URL input, progress, log area, error section. Some inconsistency in error card treatment.

**Fixes needed**:
1. Error cards in downloader (errorSection) should match the recorder's `errorCard(for:)` style with icon + label + body + buttons.
2. Downloader should add a status dot pattern for job state consistency.
3. All tool views should use the same `frame(maxWidth: toolMaxWidth, alignment: .leading)` for their main content area (not mixed `.infinity` and fixed widths).

#### the agent's Discretion
Exact spacing (8pt vs 12pt) and font size choices within each tool can stay as-is if already functional. The key is making the structural pattern consistent so any new feature can copy the template.

---

### 06-04: Extensibility Verification and Cleanup

#### Verification Method
Add a minimal placeholder feature called "Placeholder Tool" through the registry:
1. Create `FeaturePlaceholder` in `Sources/FeaturePlaceholder/FeaturePlaceholder.swift`
2. Register it in `AppComposition.swift` alongside other features
3. The placeholder should:
   - Have a metadata entry with `id`, `displayName`, `shortLabel`, `systemImage`
   - Return a simple SwiftUI view (e.g., "Placeholder: tool not yet implemented")
   - Be marked with `.producesFiles` capability
4. **Success criterion**: The placeholder appears in the sidebar, can be clicked, and shows its view. No existing feature code was modified (except adding the registration line).
5. Remove the placeholder before Phase 6 is marked complete.

#### Codebase Cleanup Opportunities
- Remove any dead code or commented-out stubs from previous phases
- Ensure `DevToolFeature` is still appropriate as a dev placeholder (or consolidate if redundant)
- Verify all `import` statements in feature modules are used
- Check that no feature directly instantiates another feature's internals (cross-feature coupling)
- Ensure the `JobLogEntry` messages are concise and useful (not raw stderr dumps with no context)

#### Registry Audit
Verify the registry pattern from Phase 1 is still clean:
- `ToolFeature` protocol: `metadata` + `makeView(context:)`
- `ToolRegistry`: `features` array with `id`-based lookup
- `ToolCapability`: `.producesFiles`, `.runsJobs`

#### the agent's Discretion
Exact placeholder view content and registration location are flexible as long as the extensibility contract is proven.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Scope And Requirements
- `.planning/ROADMAP.md` — Phase 6 goal, success criteria (UX-03, UX-04), planned slices 06-01 through 06-04, dependency on Phase 5, and phase boundary.
- `.planning/REQUIREMENTS.md` — UX-03 (concise recoverable error messages) and UX-04 (keyboard shortcuts) plus v1 traceability matrix.
- `.planning/PROJECT.md` — Core value, platform constraints, and current project state.
- `.planning/STATE.md` — Current project status and accumulated decisions affecting Phase 6.

### Prior Architecture Decisions
- `.planning/phases/01-app-foundation-and-tool-architecture/01-CONTEXT.md` — Feature registry, `ToolContext`, `ToolFeature` protocol, feature registration in `AppComposition`, and compact production-bench shell.
- `.planning/phases/02-bpm-tapper/02-CONTEXT.md` — Real-tool module pattern, compact SwiftUI surface, `onKeyPress` pattern for Space/Escape shortcuts.
- `.planning/phases/03-cubase-ready-wav-conversion/03-CONTEXT.md` — Shared job model, output inbox contract, external tool adapter pattern, WAV preset, no-shell-interpolation rule.
- `.planning/phases/04-internal-audio-recorder/04-CONTEXT.md` — Permission guidance pattern, recording state machine, error card structure, Space-based start/stop.
- `.planning/phases/05-downloader-hub/05-CONTEXT.md` — Download job flow, progress parsing, output naming, trust framing, command construction safety.

### Research Guidance
- `.planning/research/ARCHITECTURE.md` — Feature registry, ports/adapters, job runner, output inbox, and module boundaries.
- `.planning/research/PITFALLS.md` — Generic error messages, inconsistent UI, missing keyboard shortcuts, and silent helper failure.
- `.planning/research/STACK.md` — SwiftUI keyboard handling, Swift Shortcuts global vs. context-sensitive patterns.

### Prior Key Decisions (from STATE.md)
- External helper execution is centralized behind `ExternalProcessRunning` using `Process.executableURL` and argument arrays.
- yt-dlp integration must be isolated behind a service boundary.
- Helper tool packaging/licensing should be revisited before public distribution.
- The WAV converter registers as a normal `ToolFeature` with `.producesFiles` and `.runsJobs`.
- Reveal and drag readiness are both gated by `OutputHandoff`.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Sources/FeatureBPMTapper/BPMTapperView.swift` — `.focused()` + `.onKeyPress(.space)` + `.onKeyPress(.escape)` pattern for keyboard handling. Copy of `errorText` with `.foregroundStyle(.red)` for inline errors.
- `Sources/FeatureAudioRecorder/AudioRecorderView.swift` — `errorCard(for: RecorderError)` pattern with labeled icon + message + recovery buttons. Space-based start/stop. Status dot colors.
- `Sources/FeatureDownloader/DownloaderView.swift` — Download progress bar, log area, `errorSection(message:)` card format with recovery button.
- `Sources/FeatureAudioConverter/AudioConverterView.swift` — Batch row pattern with status dot, source name, status text, progress bar, and reveal/drag buttons.
- `Sources/AppCore/Jobs/Job.swift` — `JobState` enum (queued, running, completed, failed, canceled) and `JobLogEntry`.
- `Sources/AppCore/OutputInbox/OutputHandoff.swift` — Gated reveal and drag-out.
- `Sources/AppCore/Features/ToolFeature.swift` — `ToolFeatureID`, `ToolCapability`, `ToolMetadata`, and `ToolFeature` protocol.
- `Sources/OutsideCubaseHub/AppComposition.swift` — Feature registration in `AppComposition.make()`. Add new feature registration here.

### Established Patterns
- Keyboard shortcuts use SwiftUI's `.focused()` state + `.onKeyPress()` modifier. No global event monitors needed for context-sensitive shortcuts.
- Error messages appear inline (red text, 12pt) or in structured cards with icon, label, body, and buttons.
- Job state is communicated through colored dots (8pt circle), progress bars, and status text.
- Features receive `ToolContext` (provides settings, output inbox, job runner, file actions, diagnostics) and return `AnyView` via `makeView(context:)`.
- Feature registration is static in `AppComposition.make()` — one line per feature in the `features` array.

### Integration Points
- Shortcut implementation: Add `.onKeyPress()` modifiers to the tap surface (BPM), recorder surface, and input fields (downloader).
- Error standardization: Refactor `BPMTapperViewModel` error text into a card format, update downloader error section to match recorder's `errorCard` style.
- Cross-tool consistency: Align frame widths across tool views. Add status dot to downloader job state.
- Extensibility verification: Add `FeaturePlaceholder` in `Sources/FeaturePlaceholder/FeaturePlaceholder.swift`, register in `AppComposition.make()`, confirm it appears, then remove.

</code_context>

<specifics>
## Specific Ideas

- The BPM tapper's `.onKeyPress(.space)` already fires when the tap surface is focused — adding Cmd+C/Cmd+S for copy/save BPM is the natural extension.
- The recorder's Space shortcut already toggles start/stop when `recorderFocused` is true — this is the right pattern.
- Error cards across all tools should follow the same icon-label-body-button structure used in `AudioRecorderView.errorCard(for:)` — this is the most complete existing example.
- Status dots (8pt colored circles) should appear on all job-producing tools — converter batch rows have them, downloader should get them, recorder should get them (even if just for the idle/running state).
- A consistent `maxWidth` value (560-720pt depending on tool) should be used for the main tool content area.
- The placeholder verification feature should be in `Sources/FeaturePlaceholder/FeaturePlaceholder.swift` and registered as `PlaceholderFeature()` in the `features` array.

</specifics>

<deferred>
## Deferred Ideas

- Global keyboard shortcuts (like a hotkey to switch between tools) — requires macOS global event monitor and is out of scope for v1 polish.
- Menu bar extra (status item) — nice for showing active recording, but deferred to post-v1.
- Spotlight-like quick-switcher between tools — useful but deferred to post-v1.
- Custom keyboard shortcut preferences pane — the standard macOS Settings app pattern for shortcut customization is complex and deferred.

---

*Phase: 06-integration-polish-and-extensibility-check*
*Context gathered: 2026-05-11*