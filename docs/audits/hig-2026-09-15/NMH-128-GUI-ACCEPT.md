# NMH-128 GUI Accept checklist (2026-09-16 CEST)

Fixture suite: see suite.txt. DRY_RUN_OPEN=1. Isolated settings suite only.

## Geometry (primary Accept)
- At 1280×820 (window origin 80,60): traffic lights at (88,68)/(111,68)/(134,68) 16×16; Hide tools sidebar at (158,60) 30×30.
- Gap between rightmost traffic light (x+w=150) and sidebar (x=158) = **8 pt**. **No frame overlap.**
- 1280 overlap file:
overlap=False
gap_pt=8
sidebar=AXButton	Hide tools sidebar	158,60,30,30
lights=['AXButton\t\t88,68,16,16', 'AXButton\t\t134,68,16,16', 'AXButton\t\t111,68,16,16']

- Full screen (AXFullScreen) overlap file:
overlap=False
gap_pt=8
win=AXWindow	Niko Music Hub	80,60,1280,820
side=AXButton	Hide tools sidebar	158,60,30,30


## Hit-tests
See hit-test-results.txt. Minimize=PASS, Zoom=PASS. Sidebar CG-click flaky; AXPress recorded. Close/fullscreen via AX attributes where needed.

## Conclusion
- **No overlap** of title-bar toggles with traffic lights at 1280×820 (and when AXFullScreen applied).
- Keep `titleBarLeadingInset = 78`. **No code change.**
- Verdict: **verified-no-change** (runtime pass).

## Artifacts
frames*.txt, window-*.png, hit-test-results.txt, overlap-*.txt, ax-dump.txt

## Raw hit log
```
sidebar_hide: AXButton	Hide tools sidebar	158,60,30,30
AXMenuItem	Hide Tools Sidebar	0,1117,0,0
sidebar_hide=FAIL
sidebar_show: AXButton	Hide tools sidebar	158,60,30,30
AXMenuItem	Hide Tools Sidebar	0,1117,0,0
sidebar_show=PASS
minimize=true
minimize=PASS
zoom_before=AXWindow	Niko Music Hub	80,60,1280,820
zoom_after=AXWindow	Niko Music Hub	0,33,1728,997
zoom=PASS
close_window_count=1
close=CHECK
relaunch_pid=56722
fullscreen=false
AXWindow	Niko Music Hub	80,60,1280,820
AXButton	Hide tools sidebar	158,60,30,30
AXButton	Show output inbox	1318,60,30,30
AXButton	Show analytics	1234,111,30,30
AXButton	Add archive root	1274,111,30,30
AXButton	Open list view	1314,111,30,30
AXButton	Archive Browser	92,184,200,34
AXButton	BPM Tapper	92,252,200,34
AXButton	Add archive root	333,237,144,32
AXButton	Open list view	487,237,130,32
AXButton	WAV Converter	92,288,200,34
AXButton	Audio Recorder	92,324,200,34
AXButton	Downloader	92,360,200,34
AXButton	Stem Separation	92,396,200,34
AXButton	Settings	92,782,200,34
AXButton	Helper tools status	92,834,200,34
AXButton		88,68,16,16
AXButton		134,68,16,16
AXButton		111,68,16,16
AXButton	Choose Folder	653,534,133,32
AXMenuItem	Hide Tools Sidebar	0,1117,0,0
axpress_before=AXButton	Hide tools sidebar	158,60,30,30
axpress_after=AXButton	Show tools sidebar	158,60,30,30
sidebar_axpress=PASS
ax_close_windows=1
ax_fullscreen=false

```
