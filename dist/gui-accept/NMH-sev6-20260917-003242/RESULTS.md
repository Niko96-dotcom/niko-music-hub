# Sev6 + Sev7 GUI Accept — 2026-09-17 ~00:45 CEST

Proof: `dist/gui-accept/NMH-sev6-20260917-003242/`
Suite: `NikoMusicHubGUIAcceptSev6.5B96CFFC-96D1-4F21-A3AC-5155F06842F2`
Fixture: `Fixtures/CubaseArchive` + `DRY_RUN_OPEN=1` + isolated outputFolder under this proof's `isolated-output/`.
App binary reused from tip-matched sev45 build (Accept-only tip; no app code change). Launch via `open --env`.

| ID | Verdict | Evidence |
|----|---------|----------|
| NMH-068 | **PASS** (caveat) | Appearance Light/Dark/Follow System + help `Overrides the system appearance…` (`ax-settings.txt`); Light persists after relaunch (`appearance=light` in `ax-068-defaults.txt`). System Auto while Light not toggled (asleep). |
| NMH-069 | **IAR** | Inactive vibrancy needs side-by-side inactive window visual — not proven unattended. |
| NMH-070 | **PASS** | Settings captions 44.1 kHz / 24-bit / Preserve mono/stereo; **Edit in WAV Converter** selected WAV Converter (`ax-070-wav.txt`). |
| NMH-072 | **PASS** | Visible `Scan exclusions` + `TextField("Scan exclusions")` + hint (`ax-072-archive.txt` / `ax-072-field-attrs.txt`). AXTitle not exposed (SwiftUI); same pattern as NMH-032. |
| NMH-027 | **PASS** | Comment `Accent is a locked grey…` in HubDesignSystem.swift; `testAccentIsNeutralNotTinted` PASS (`unit-tests.txt`). System Settings accent Red visual skipped (asleep). |
| NMH-075 | **PASS** | Title-bar help verb phrases `Hides the tools column` / `Hides the Output Inbox` (`ax-settings.txt`); sidebar tool rows help empty. |
| NMH-078 | **PASS** | `testDesignSystemPreviewForcesAppearanceVariants` PASS. Xcode canvas not opened unattended. |
| NMH-082 | **PASS** | Stem intake AX `Drop an audio file or choose a file to separate` + hint; unit `testIntakeWellAccessibilityLabelIsDeclared` PASS (`ax-stem.txt`). |
| NMH-084 | **PASS** | List empty+scanning branch uses mini `ProgressView` + `Scanning archive…`; no `arrow.triangle.2.circlepath` (`src-084-empty-branch.txt`). Mid-scan spinner not caught (fixture already loaded). |
| NMH-087 | **PASS** | Analytics overview `Bar chart of project saves by month for the last 12 months.` before bars (`ax-087-analytics.txt`). |
| NMH-089 | **PASS** | Filters menu shows shelf name (`All songs` → `Quiet Songs`) + help `Filters and shelves` (`ax-089-after-q.txt`). |
| NMH-092 | **PASS** | Diagnostics sheet: `Companion notes`, `Short preview files (not the main mix)`, `Export diagnostics` (`ax-092-sheet.txt`). |
| NMH-066 | **PASS** (caveat) | Source exclusive `.primary` via `primaryIntake` (`StemSeparationView.swift`); both actions present in AX. Filled-primary visual style not AX-readable; YouTube URL enabled state stayed disabled (helper). |
| NMH-096 | **PASS** | Alert title `Clear History?` + message `Removes saved BPM history. The current tap run is kept.` + Cancel (`ax-096-alert.txt`). |
| NMH-097 | **PASS** (caveat) | Unicode `…` in Recorder/Downloader copy; failed header uses `Colors.danger` (`src-097-*`). Failed-header color not runtime AX-proven this pass. |
| NMH-127 | **PASS** | `Window("Niko Music Hub", id: "main")` (not WindowGroup); no New Window menu item; window count stayed 1 (`ax-127-*`). |
| NMH-130 | **IAR** | Resized to 1100×752@120,80; after quit/relaunch returned to 1400×900@40,40 (`ax-130-*`). `isRestorable`+`hub.main` present in source but frame not restored. |
| NMH-131 | **IAR** | Contrast matrix / Increase Contrast skipped (asleep System Settings). |
| NMH-132 | **IAR** | Menu-bar light/dark visual skipped. |
| NMH-133 | **IAR** | Full Keyboard Access System Settings skipped (asleep). |
| NMH-135 | **PASS** → verified-no-change | `AppIcon.icns` present (1024²) + `AppLogo-48/96.png` (`ax-135-*`). |
| NMH-140 | **PASS** | Compact empty stages On; columns named `{title} column, N songs` in AX; source `.help(column.title)` (`ax-140-*`). |

Leftover sev3/5 (006/035/088/024/025/038/043/074): **skipped** — asleep-only System Settings / RTL / sheen / VO-only / weak AX selection proofs unchanged.
