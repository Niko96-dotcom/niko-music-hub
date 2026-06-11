# Pitfalls Research

**Domain:** yt-dlp downloader hardening in a native macOS app
**Researched:** 2026-06-11
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: Progress That Cannot Appear

**What goes wrong:**
The UI waits for progress lines that the real yt-dlp invocation never emits.

**Why it happens:**
Tests use fabricated `[download] 45%` lines while the command uses `--print after_move:...`, which changes output behavior and can leave only final printed lines.

**How to avoid:**
Pass `--progress` and an explicit progress template such as `download:NIKO_PROGRESS:%(progress._percent_str)s`. Parse only `NIKO_PROGRESS:` for UI progress.

**Warning signs:**
Progress bar stays at 0% while Terminal proves the download is active.

**Phase to address:**
First v1.4 implementation phase.

---

### Pitfall 2: Total Timeout Kills Valid Work

**What goes wrong:**
Long/slow downloads are terminated after 90 seconds even when healthy.

**Why it happens:**
The same timeout model is used for short health/simulate calls and full media downloads.

**How to avoid:**
Keep fixed timeouts on health/simulate. For downloads, track last output/progress time and fail only after a stall window.

**Warning signs:**
Short videos pass; longer videos, WAV extraction, 720p merges, or throttled connections fail "sometimes."

**Phase to address:**
First v1.4 implementation phase, after real progress markers.

---

### Pitfall 3: Logs Become The Data Plane

**What goes wrong:**
The downloader writes synthetic destination log lines, then UI code regex-parses logs back into file URLs.

**Why it happens:**
Job logging was convenient before the output-inbox contract needed richer media handoff.

**How to avoid:**
Pass output URLs through a typed result/handoff path. Keep logs as diagnostics only.

**Warning signs:**
Changing log copy breaks inbox ingestion; output rows appear without reveal/open/drag actions.

**Phase to address:**
Second v1.4 implementation phase.

---

### Pitfall 4: Helper Health Exists But Does Not Warn

**What goes wrong:**
yt-dlp is stale enough to fail on site extractor changes, but the app reports it as available.

**Why it happens:**
`YtDlpAvailability.outdated` exists, but `YtDlpHealthChecker.availability` never emits it.

**How to avoid:**
Parse date-like version tags, compare to a staleness policy, and show update guidance. On this machine, local yt-dlp is `2026.03.17`; latest checked release is `2026.06.09`.

**Warning signs:**
Terminal `brew upgrade yt-dlp` fixes failures the app classified as random downloader errors.

**Phase to address:**
Second v1.4 implementation phase.

---

### Pitfall 5: Format Validation Does Not Match Download

**What goes wrong:**
Preflight succeeds while the selected real format later fails.

**Why it happens:**
Simulation omits selected `-f` and post-processing args, and does not force single-video behavior with `--no-playlist`.

**How to avoid:**
Simulate the selected format path and add `--no-playlist` unless/ until playlist UX is intentionally scoped.

**Warning signs:**
Changing from MP3 to MP4 or 720p changes failure behavior after enqueue, not during preflight.

**Phase to address:**
First or second v1.4 implementation phase.

---

### Pitfall 6: UTF-8 Streaming Drops Lines

**What goes wrong:**
A split multibyte character makes a streaming chunk fail UTF-8 decoding; if that chunk contains the final file marker, the app reports no output files.

**Why it happens:**
`ExternalProcessRunning` converts each pipe chunk independently instead of using an incremental decoder or parsing the full accumulated output as fallback.

**How to avoid:**
Buffer bytes until valid UTF-8 boundaries, or always re-parse `ExternalProcessResult.standardOutput` and `standardError` at process end.

**Warning signs:**
Failures correlate with titles containing non-ASCII characters.

**Phase to address:**
First v1.4 implementation phase if touching process streaming; otherwise second.

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Assert source strings in tests | Fast to write | Does not prove behavior | Only as a guardrail next to behavioral tests. |
| One output handoff policy | Simple API | Blocks media outputs | Not acceptable for v1.4. |
| `try?` store errors | Quiet UI | Data loss or silent stale state | Only for best-effort refresh, with diagnostics. |
| Premerged-only MP4 selectors | Simple output extension | Lower quality/fallback surprises on modern sites | Accept only as one explicit "compatibility" option, not the 720p default. |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| yt-dlp progress | Parse normal stdout | Use `--progress-template` markers. |
| yt-dlp update state | Only check executable exists | Run `--version`, parse date, and guide update. |
| FFmpeg path | Assume app `PATH` matches Terminal | Continue using `--ffmpeg-location` and resolver environment. |
| Output inbox | Reveal only WAV | Tool-aware media allowlist. |
| Retry logic | Match only one timeout wording | Include `timed out`, socket/read timeout, connection reset, HTTP 5xx, temporary failures. |

## "Looks Done But Isn't" Checklist

- [ ] **Progress:** The progress test uses the same marker emitted by the real command.
- [ ] **Timeout:** There is no fixed total timeout on actual downloads.
- [ ] **Health:** The stale yt-dlp path shows user-facing update guidance.
- [ ] **Simulation:** Simulate includes selected format args and `--no-playlist`.
- [ ] **Output:** Inbox receives typed output URLs without log parsing.
- [ ] **Handoff:** MP3/M4A/MP4/WEBM can be revealed/opened/dragged when safe.
- [ ] **UAT:** A real network downloader check covers a longer or throttled case, not only an 18-second video.

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Progress cannot appear | Phase 26 | Captured command args include `--progress-template`; parser accepts `NIKO_PROGRESS:`; UI progress advances. |
| Total timeout kills work | Phase 26 | Tests prove no 90-second request timeout for downloads and stall timeout behavior is covered. |
| Logs as data plane | Phase 27 | Output inbox tests fail if synthetic log-line parsing is removed from the job path. |
| Helper health dead code | Phase 27 | Date-version tests cover available/outdated/unusable states. |
| Format mismatch | Phase 26 or 27 | Simulate request contains selected format args and `--no-playlist`. |
| Missing UAT | Final v1.4 phase | Evidence file includes real/live or opt-in network verification. |

## Sources

- 2026-06-11 downloader audit.
- Official yt-dlp README: https://github.com/yt-dlp/yt-dlp.
- Local helper version checks and local source/test inspection.

---
*Pitfalls research for: v1.4 Downloader Reliability*
*Researched: 2026-06-11*
