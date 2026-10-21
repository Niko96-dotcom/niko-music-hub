# Archive board horizontal scrolling — 21 October 2026

## Cause and implementation

Base: `0628ccc`. Its `ArchiveBoardLanesView.swift` used a SwiftUI horizontal
`ScrollView`, with each lane's geometry preference fed back into `@State` on
horizontal offset changes. Moving the independently hosted native lanes repeatedly
entered SwiftUI/AppKit layout. An eight-second scrolling `sample` attributed
1,168 of 2,984 main-thread samples to the window layout subtree, including 645
in `NSHostingView.layout`. These are inclusive sample weights, not frame counts.

Direct-to-outer and over-card input both reproduced the CPU cost. Clean lateral
and diagonal input reached the outer view without vertical drift. There was no
scroll snapping. Changing only geometry storage to a non-observable reference
did not reliably improve the result; the expensive SwiftUI scrolling boundary
remained.

The final implementation uses one native viewport whose document directly
contains the **existing eight column drop hosts**. It adds no SwiftUI hosting
graph. Column presentation equality uses the catalog's shared-storage comparisons;
the viewport accepts its proposed size without fitting the hosted document.
Frame layout is bounded by the lane count. Scroll offsets never enter SwiftUI
state; drag edge scrolling reads current native rectangles on demand.

`ArchiveBoardNativeSongListView.scrollWheel` forwards the **original** lateral
event to the shared viewport, preserving phases and terminal momentum across
lanes. Lane horizontal elasticity is disabled; vertical input remains native.
Responsive-scrolling compatibility is explicit because overriding `scrollWheel`
otherwise changes AppKit's eligibility decision. The reusable tables, row pools,
height measurements, fresh offscreen data and retained detail navigation remain.
Hidden columns continue receiving current values. Accepted-drop transactions
cross the native boundary explicitly.

Hover bookkeeping holds callbacks only for the card and play control under the
pointer. It has no per-card publishers, extra tracking views or SwiftUI scroll
publications. Scroll start clears hover without animation, passing cards produce
no hover state writes, and idle restores only the current hover. Reused rows and
detached boards release callbacks. Background cross-fades, selection, row
membership/entrance and drag edge movement share a 160 ms ease-out. Reduce Motion
disables optional motion; no springs or focus rings were added.

Preservation checks rejected a prototype with an additional SwiftUI lane host and
per-card hover subscriptions: detail return rose from about 62 to 73 ms. Native
per-card tracking views also cost more. These are diagnostic variants, not the
final result. Explicit presentation equality and reusing the column hosts are
covered by regression tests.

## Measurement method

- Release modules, M1 Ultra, macOS 27.0.1, Swift 6.4; generator seed 20261018,
  **10,000 songs / 157,639 files**, seeded metadata, 3,042 No Status rows.
- Every process copies the same database, uses isolated settings and hosts the
  real `ArchiveBrowserView`. It waits for scan completion plus one second. The
  main thread explicitly uses user-interactive QoS. No real archive is used.
- Three alternating base/candidate launches per experiment. No build, test or
  profiler overlaps scored runs. Other users of the shared host are not stopped.
- Horizontal: fixed-point hit testing over cards; direct outer input, lateral,
  diagonal, initial vertical wobble, direct lane and unphased mouse cases.
  **228 events per case per launch**, in both directions, including finger and
  momentum phases. An 8 ms run-loop interval separates steps. CPU includes
  deferred layout/display work; an idle control separates steady hosting cost.
- Direct synchronous injection has no WindowServer stream for AppKit's concurrent
  gesture tracker to consume. The **harness alone** disables that tracker equally
  for both binaries. Preservation runs omit `horizontal` and retain normal
  responsive-scrolling eligibility.
- Preservation: vertical wheel steps, oldest-card reachability, all-lane jumps and
  traversal, detail open/return, immediate search, stage changes and catalog apply.
  Timed operations include model mutation, layout, display and transaction flush.
  Each measured operation has one warmup and three trials per launch. Reachability
  requires the **entire actual oldest card** inside the native clip viewport.
- These are input-routing/CPU/layout measurements, **not compositor frame times**.
  Paced-step durations include the deliberate 8 ms interval. Footprint is physical
  memory sampled at the named checkpoint; it is not a live-object count or a
  repeat of the earlier report's 60-second cached-launch memory experiment.

## Final results

Horizontal CPU is median (min–max) of the **three per-launch mean CPU costs**.
All launches include the same 228 events per scenario. Mean cost is the primary
metric because rendering is intermittent and per-event medians can move sharply
with display cadence.

| Main-thread CPU per event | Base, ms | Final, ms |
| --- | --- | --- |
| Idle control | 0.99 (0.90–1.05) | 0.92 (0.88–0.96) |
| Direct outer input | 4.56 (4.50–4.82) | 2.86 (2.48–2.94) |
| Over cards, horizontal | 4.57 (4.06–4.87) | 3.12 (3.00–3.25) |
| Over cards, diagonal | 4.28 (4.05–4.92) | 2.83 (2.44–2.89) |
| Over cards, initial vertical wobble | 4.61 (4.27–4.75) | 2.49 (2.36–2.93) |
| Direct lane input | 4.53 (4.47–4.60) | 2.88 (2.81–2.90) |
| Over cards, unphased mouse wheel | 6.83 (6.56–6.95) | 4.07 (3.88–4.27) |

Average horizontal CPU cost falls **32%** over cards, and **40%** for the
unphased mouse wheel. Over-card paced-step p95 falls **18.45 → 15.80 ms**
(17.02–18.50 vs 15.30–16.45), including the intentional 8 ms interval. Per-event
CPU medians are 6.76 → 0.34 ms, with broad baseline variation (0.63–6.98 vs
0.30–0.37); those medians alone would overstate the improvement.

Horizontal and diagonal cases have zero vertical drift in all six launches;
the wobble case retains the expected initial 6-point vertical movement. All
eight native lane instances survive. Realized cell counts at the end are **38
in both builds**, in all launches. Footprint after the horizontal matrix is
**236.36 → 234.14 MiB** (235.97–236.49 vs 232.84–236.11). Fresh-scan launch
footprint is 225.67 → 223.27 MiB (224.69–226.17 vs 222.34–225.80). The ranges
overlap; no material memory reduction is claimed.

Preservation results below are median (min–max) of the three per-launch medians,
in milliseconds. Both builds reach the fully visible oldest card **12/12 times**,
including warmups.

| Operation | Base | Final |
| --- | --- | --- |
| Detail → board | 72.08 (70.66–81.56) | 67.37 (60.99–83.64) |
| Fully visible oldest card, largest lane | 16.92 (14.78–21.63) | 19.46 (16.92–20.76) |
| Vertical 120-point step, top | 6.63 (6.62–6.87) | 6.76 (6.01–6.81) |
| Vertical step, middle | 7.21 (6.99–7.23) | 6.89 (6.33–7.14) |
| Vertical step, oldest | 6.83 (6.62–6.96) | 6.65 (6.56–6.80) |
| Jump every lane to its oldest | 81.29 (78.97–88.08) | 80.75 (78.68–83.18) |
| Traverse every lane, ten depths | 90.49 (89.30–106.47) | 100.25 (89.27–103.14) |
| Old-song board search, immediate | 130.02 (128.08–131.54) | 121.14 (120.70–127.68) |
| Recent-song board search, immediate | 137.10 (136.53–140.11) | 131.38 (126.53–131.41) |
| Absent board search | 86.94 (86.41–90.12) | 82.92 (82.58–83.90) |
| Open oldest detail | 100.83 (95.54–100.85) | 95.03 (93.73–98.95) |
| Open recent detail | 129.37 (125.74–130.66) | 122.28 (120.35–125.48) |
| Stage change, old song | 179.84 (179.81–189.43) | 178.10 (173.55–184.84) |
| Stage change, recent song | 181.91 (173.61–182.19) | 184.13 (162.20–185.02) |
| Apply unchanged catalog, board | 45.60 (44.30–46.21) | 38.41 (38.10–41.58) |

Vertical wheel cost, actual oldest-card reachability and retained detail return
remain within the matched baseline spread. The bulk traversal point estimate is
higher; its ranges overlap fully. Mean cost over all 30 depth steps is
94.91 → 98.93 ms (per-launch means 88.73–103.97 vs 94.43–101.30). These runs do
not establish a bulk-traversal improvement or a systematic regression. It remains
an explicit uncertainty rather than being omitted from the report. List wheel,
search and catalog-apply costs likewise overlap the baseline ranges.

After the full preservation sequence, footprint is **504.86 → 492.31 MiB**
(499.78–506.17 vs 488.88–494.13). This includes list traversal and repeated model
updates, so it must not be compared directly with a quiet cached launch.

## Validation and limits

- **70 scoped XCTest cases** passed, including native column/row reuse, current
  selection/metadata/Vault activity, hidden-lane values, current interaction owner,
  compaction/drop expansion, viewport resize, drag clamping/RTL, original lateral
  events, terminal momentum, hover suppression and explicit equality.
- `./script/ci.sh` through Terminal.app: exit 0, **2,781 XCTest cases, 8 expected
  skips, 93 Swift Testing cases**, plus the deterministic recorder and script
  gates. No CoreAudio probe timing failures occurred in that environment.
- Hosted geometry: all **8 lane rectangles and 36 visible card rectangles match
  the base exactly**. No Status cards retain 204-point width, 68/75-point heights
  and 6-point gaps. Dark `cacheDisplay` captures are byte-identical (SHA-256
  `579f6ccfc6132fa07ddebb2887538c2f22bfbd2da7f5f33294fb233fb68aa66e`).
- Light appearance also has identical lane/card frames and byte-identical pixels
  (SHA-256 `33d0dab28670b570d77d14968ee1d191d68dc38f62af217270577836d9abf52a`).
- The shell lacks AX and Screen Recording access. Physical trackpad feel,
  compositor pacing, installed-bundle UI acceptance and owner acceptance remain
  unverified. No release, push, merge or real-archive transfer is performed.

## Reproduce and local evidence

Binaries: `.build/performance-startup/archive-launch-scroll-base` and
`archive-launch-scroll-final`. The base was built by saving candidate sources
under `.build/`, restoring base files with `git show` **in this worktree**, then
restoring the candidate in `finally`. No other checkout was changed. Both binaries
use the same measurement path in `script/performance/archive-launch.swift`.
Binary SHA-256 receipts:

- Base: `686f896ebba780c0b3695c05ef58e4f408b54d507d9496679e87951cb1753357`
- Final: `0ceb87c2149b67ff06cf544926ce2554ea9a095de3492431237031dcad2f4647`

```bash
export BAKEOFF_NAME=scroll
export NMH_BENCH_ARCHIVE="$PWD/.build/scroll-measurements/data/CubaseArchive"
export NMH_BENCH_DATABASE="$PWD/.build/scroll-measurements/data/seed.sqlite"
export NMH_SCROLL_APPEARANCE=dark
script/performance/ab.sh launch .build/scroll-measurements/final-horizontal 3 \
  scroll-base scroll-final --scenarios horizontal --runs 3
script/performance/ab.sh launch .build/scroll-measurements/final-preservation 3 \
  scroll-base scroll-final --scenarios back,reach,wheel,scroll,detail,search,apply,stage --runs 3
```

Raw synthetic JSON and stderr remain in those directories. Diagnostic variants
and `scroll-base.sample` are separate from scored final runs. `targeted-current.log`
and `targeted-verified-final.log` hold the scoped checks; `ci-verified.log` and
`ci-verified.exit` hold the final full gate. `NMH_SCROLL_ARTIFACTS=<project-directory>`
saves `NSView.cacheDisplay` pixels plus native frame rectangles in the JSON;
`NMH_SCROLL_APPEARANCE=light|dark` selects appearance for capture. No measurement
code is embedded in the product.
