# Pitfalls Research

**Domain:** Native macOS music-production utility hub
**Researched:** 2026-05-04
**Confidence:** MEDIUM-HIGH

## Critical Pitfalls

### Pitfall 1: System Audio Capture Fails Late

**What goes wrong:**
The app shell and UI get polished, but internal audio recording fails because permissions, macOS version, output routing, or API behavior were not proven.

**Why it happens:**
Desktop audio capture looks like a UI feature, but the hard part is the OS integration.

**How to avoid:**
Build a minimal Core Audio tap to WAV proof early, including permission copy, failure states, and a real playable WAV output.

**Warning signs:**
Recorder UI exists before a verified WAV file; errors say only "failed"; no macOS version check.

**Phase to address:**
Phase 4 at latest, with a technical proof earlier if Phase 1 planning finds uncertainty.

---

### Pitfall 2: External Tool Commands Become Unsafe or Untestable

**What goes wrong:**
yt-dlp/FFmpeg commands are built as shell strings inside UI code, causing path bugs, escaping bugs, and poor tests.

**Why it happens:**
Command-line tools are quick to prototype and easy to let leak through the app.

**How to avoid:**
Use `Process` with explicit executable URL and argument array. Keep command construction in adapters with unit tests.

**Warning signs:**
Code contains `sh -c`, string-concatenated URLs, or command snippets in view models.

**Phase to address:**
Phase 1 and Phase 3.

---

### Pitfall 3: WAV Output Is Technically Valid But Annoying in Cubase

**What goes wrong:**
WAV files import but have wrong sample rate, bit depth, channels, clipping, or names, creating work inside Cubase.

**Why it happens:**
Conversion is treated as "any WAV" instead of "production-ready WAV".

**How to avoid:**
Create project output presets, verify WAV headers, and expose sample rate/bit depth/channel settings.

**Warning signs:**
No tests inspect output format; no default preset; user has to rename every output manually.

**Phase to address:**
Phase 3 and Phase 4.

---

### Pitfall 4: Feature Hub Becomes a Hard-Coded Dashboard

**What goes wrong:**
Adding the next idea requires editing navigation, state, settings, job UI, and output code in multiple places.

**Why it happens:**
The first three tools feel small enough to wire directly.

**How to avoid:**
Create a feature registry, shared tool context, and common job/output services before building all tools.

**Warning signs:**
Each feature owns its own progress UI; sidebar has hard-coded cases; settings are feature-specific globals.

**Phase to address:**
Phase 1.

---

### Pitfall 5: Downloader Scope Crosses Legal or Trust Boundaries

**What goes wrong:**
The app appears to encourage downloading restricted material or hides what yt-dlp is doing.

**Why it happens:**
Downloader convenience can blur source rights and site rules.

**How to avoid:**
Use explicit URL input, show source/output details, and document that downloads are for material the user has rights to access and save.

**Warning signs:**
"Download anything" language, browser-cookie automation in v1, or silent retries against protected sources.

**Phase to address:**
Phase 5.

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Start with no feature registry | Faster first view | Every new tool rewrites shell/navigation patterns | Never; registry can be tiny. |
| Use one global settings object for all tools | Easy access | Settings become tangled and hard to migrate | Only for shared app-level settings. |
| Assume Homebrew paths | Quick local development | Breaks on other machines and Intel/Apple Silicon differences | Acceptable only with visible health checks. |
| Skip output metadata | Saves persistence work | Output inbox cannot show source, format, or job status | Only for throwaway proof code. |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Core Audio taps | Missing Info.plist usage description or version gating. | Add permission text, version check, and explicit error states. |
| yt-dlp | Treating all stderr as failure. | Parse process exit status and progress carefully. |
| FFmpeg | Assuming one command fits all audio inputs. | Build requests from explicit presets and inspect output. |
| App Sandbox | Expecting arbitrary file access. | Use user-selected folders or defer sandboxed distribution. |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Running conversion/download on main actor | UI freezes during long jobs. | Job runner uses async background work. | Immediately with large files. |
| Loading full audio into memory | High memory use or crashes. | Stream buffers when converting/recording. | Long recordings or batch conversion. |
| Unbounded parallel jobs | CPU/disk saturation. | Queue with concurrency limits and cancellation. | Multiple downloads/conversions. |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Shell interpolation with URLs/paths | Injection or broken commands. | `Process` executable + args only. |
| Silent helper binary updates | Trust and integrity risk. | Show version, source, and update action; verify where possible. |
| Capturing audio without clear state | Privacy/trust issue. | Obvious recording indicator, duration, and stop control. |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Generic error messages | User cannot recover mid-session. | "FFmpeg not found", "permission denied", "unsupported source" with next action. |
| Hiding output files | Dragging into Cubase stays annoying. | Shared output inbox with reveal and drag-out. |
| Over-explaining in the UI | App feels like docs, not a tool. | Clear controls, terse labels, detailed errors only when needed. |
| Too much chrome around tiny tools | BPM tapper feels slower than the website. | Compact, keyboard-friendly tool panels. |

## "Looks Done But Isn't" Checklist

- [ ] **BPM tapper:** Often missing reset/half/double/copy - verify each is one action.
- [ ] **Recorder:** Often missing real system audio proof - verify a playable WAV from computer audio.
- [ ] **Converter:** Often missing output format inspection - verify sample rate, bit depth, channels.
- [ ] **Downloader:** Often missing helper health and legal scope - verify tool version and explicit URL workflow.
- [ ] **Output inbox:** Often missing drag-out - verify generated WAV can be dragged into another app/Finder.
- [ ] **Architecture:** Often missing a second feature registration test - verify a dummy feature can be added without shell edits.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Audio capture path fails | MEDIUM-HIGH | Spike ScreenCaptureKit fallback or virtual-device path before adding recorder polish. |
| Helper packaging becomes blocked | MEDIUM | Keep external-tool health check and document install path; defer bundled distribution. |
| Architecture becomes coupled | MEDIUM | Extract feature registry and ports before adding the next feature. |
| WAV specs wrong | LOW-MEDIUM | Add output inspection tests and preset-driven conversion. |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Hard-coded feature hub | Phase 1 | Add dummy feature through registry. |
| WAV output mismatch | Phase 3 | Inspect converted WAV headers. |
| System audio capture fails late | Phase 4 | Record internal audio to a playable WAV. |
| Unsafe command construction | Phase 3 and Phase 5 | Unit-test argv arrays; no shell interpolation. |
| Downloader trust/legal ambiguity | Phase 5 | Explicit source URL and rights-aware UI copy. |

## Sources

- https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps - Audio capture permission/version gotchas.
- https://support.apple.com/en-lamr/guide/mac-help/mchl592e5686/mac - User-facing screen/system audio recording permission context.
- https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox - File access constraints.
- https://github.com/yt-dlp/yt-dlp/blob/master/README.md - Downloader dependencies, release files, and update behavior.
- https://ffmpeg.org/ffmpeg.html - FFmpeg conversion behavior and argument model.

---
*Pitfalls research for: Native macOS music-production utility hub*
*Researched: 2026-05-04*
