# Menu Bar Quick Access

Niko Music Hub adds a menu bar status icon (a waveform) that provides instant access
to the production tools without switching to the app first.

## Menu entries

| Entry | Action |
|-------|--------|
| Audio Recorder | Brings the app forward with the Recorder tool selected |
| WAV Converter | Brings the app forward with the WAV Converter selected |
| BPM Tapper | Brings the app forward with the BPM Tapper selected |
| Downloader | Brings the app forward with the Downloader selected |
| Stem Separation | Brings the app forward with the Stem Separation tool selected |
| Output Inbox | Brings the app forward and reveals the Output Inbox panel |

Stem download workflows route to Stem Separation — there is no separate
download-to-stems entry in the menu (ROUT-06).

## Why direct job controls are not in the menu (v1.8)

Record, convert, download, and separate controls are not accessible from the menu bar.
Each tool surface already owns permissions, progress display, cancellation, drag-and-drop
intake, and error messaging. The menu bar is a thin launcher, not a second control surface.
Adding per-job controls to the menu would duplicate that logic and risk state divergence
between the menu and the tool view. This is tracked as FUT-04 for a future milestone
when lifecycle and permission safety for remote job dispatch are designed.

## Implementation note

The menu bar routing is implemented as a headless `QuickAccessRouter` model layer that
receives typed commands (`QuickAccessCommand`) from the menu and drives `AppShellView`
state. It does not construct tool views and does not interact with the output-handoff
allowlist (HAND-04). See `Sources/AppCore/QuickAccess/` for the routing contract.
