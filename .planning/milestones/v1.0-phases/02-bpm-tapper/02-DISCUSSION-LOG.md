# Phase 2: BPM Tapper - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md - this log preserves the alternatives considered.

**Date:** 2026-05-04T15:25:03+02:00
**Phase:** 2-BPM Tapper
**Areas discussed:** Tap Feel, Tempo Estimator, Result Actions, History Shape

---

## Tap Feel

### What should count as a tap?

| Option | Description | Selected |
|--------|-------------|----------|
| Focused tap zone | Clicks only count inside the BPM tool's big tap surface; keyboard taps count when the BPM tool is active. | yes |
| Whole tool surface | Clicks anywhere in the BPM panel count as taps, with buttons excluded. | |
| Global-ish window shortcut | Spacebar taps work whenever the app window is focused, even if a control is not. | |

**User's choice:** Focused tap zone
**Notes:** This keeps tapping predictable and avoids accidental panel clicks counting as tempo input.

### Which keyboard input should tap tempo use?

| Option | Description | Selected |
|--------|-------------|----------|
| Spacebar only | Familiar for tap tempo, low mental load. | yes |
| Spacebar + T | Gives a letter-key backup if space conflicts with focused controls. | |
| Spacebar + Return | Easy to hit, but Return can feel like submit/save in macOS UI. | |

**User's choice:** Spacebar only
**Notes:** No extra tap keys were requested.

### How should the tool treat a long pause between taps?

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-start a new run | After a short timeout, the next tap clears old intervals and starts fresh. | yes |
| Keep old taps until reset | Predictable, but stale taps can poison the estimate. | |
| Show stale state, ask reset manually | Explicit but slower during a music session. | |

**User's choice:** Auto-start a new run
**Notes:** Planner should choose and test the exact timeout threshold.

### What should reset feel like?

| Option | Description | Selected |
|--------|-------------|----------|
| Dedicated Reset button + Escape | Visible button, fast keyboard clear. | yes |
| Dedicated Reset button only | Simpler, but slower while tapping. | |
| Double-click tap zone resets | Compact, but risky because double-clicks can be accidental taps. | |

**User's choice:** Dedicated Reset button + Escape
**Notes:** Reset must be visible and keyboard-fast.

---

## Tempo Estimator

### How should BPM be calculated once enough taps exist?

| Option | Description | Selected |
|--------|-------------|----------|
| Recent interval average | Average the most recent few tap intervals, with guardrails for weird taps. | yes |
| Median recent interval | More resistant to one bad tap, but can feel less responsive. | |
| Weighted recent average | Newest taps matter more, so it reacts faster, but may jump more. | |

**User's choice:** Recent interval average
**Notes:** Keep the estimator understandable and testable.

### How many recent taps should drive the estimate?

| Option | Description | Selected |
|--------|-------------|----------|
| Last 4 intervals | Quick to settle, still responsive. | yes |
| Last 8 intervals | Steadier for long tapping, slower to react. | |
| Adaptive window | Start small, grow as confidence improves. | |

**User's choice:** Last 4 intervals
**Notes:** Responsiveness matters more than long-window smoothing for this first tool.

### When should the UI first show a BPM number?

| Option | Description | Selected |
|--------|-------------|----------|
| After 2 taps | Immediate feedback, then stabilizes as more taps arrive. | yes |
| After 3 taps | Avoids a one-interval guess feeling too official. | |
| After 4 taps | Steadier first number, but less instant. | |

**User's choice:** After 2 taps
**Notes:** The first estimate should appear immediately after one interval exists.

### How should obvious outlier taps be handled?

| Option | Description | Selected |
|--------|-------------|----------|
| Ignore extreme intervals | If a tap interval is wildly outside the recent pattern, exclude it from the estimate but keep tapping going. | yes |
| Restart on extreme interval | Treat a huge mismatch as a new run. | |
| Never ignore taps | Every tap counts exactly, even mistakes. | |

**User's choice:** Ignore extreme intervals
**Notes:** Outlier handling should not force a full restart.

---

## Result Actions

### How should half-time and double-time work?

| Option | Description | Selected |
|--------|-------------|----------|
| Adjustment mode | Half/Double changes the displayed/saved result while preserving the original tapped BPM as context. | yes |
| Destructive transform | Half/Double replaces the current estimate as if that was the tapped BPM. | |
| Quick copy variants only | Do not change display; just offer copy half/copy double actions. | |

**User's choice:** Adjustment mode
**Notes:** Original tapped BPM remains meaningful context for adjusted values.

### What should copy put on the clipboard?

| Option | Description | Selected |
|--------|-------------|----------|
| Plain number | Example: 128. | yes |
| Number + BPM | Example: 128 BPM. | |
| Rich summary | Example: 128 BPM (tapped 64, doubled). | |

**User's choice:** Plain number
**Notes:** Optimized for fast paste into production tools or notes.

### How should Save behave?

| Option | Description | Selected |
|--------|-------------|----------|
| One-click save current result | Save immediately to local history using the current adjusted display value. | yes |
| Save with optional note prompt | Useful for context, but interrupts the flow. | |
| Auto-save every copied result | Convenient, but can make history noisy. | |

**User's choice:** One-click save current result
**Notes:** Saving should not interrupt tapping.

### What should happen after Copy or Save succeeds?

| Option | Description | Selected |
|--------|-------------|----------|
| Small inline confirmation | Subtle Copied/Saved state near the action. | yes |
| System notification | Visible outside the app, but too loud for repeated taps. | |
| No confirmation | Fastest, but easier to wonder if the action worked. | |

**User's choice:** Small inline confirmation
**Notes:** Feedback should be quiet and local to the tool.

---

## History Shape

### What should each saved BPM entry contain?

| Option | Description | Selected |
|--------|-------------|----------|
| BPM + timestamp + adjustment context | Saved value, when it was saved, and whether it was original/half/double. | yes |
| BPM + timestamp only | Very simple, but loses why a value differs from tapped tempo. | |
| BPM + timestamp + editable note | Richer, but turns save into more of a filing action. | |

**User's choice:** BPM + timestamp + adjustment context
**Notes:** History keeps useful tempo context without notes.

### How much history should the BPM tool show in the main view?

| Option | Description | Selected |
|--------|-------------|----------|
| Recent list in the tool | Show the latest few saved BPMs beside/below the tapper. | yes |
| Collapsed history drawer | Cleaner main surface, but one more action to reach saved tempos. | |
| No visible history until saved | Minimal, but hides a required feature. | |

**User's choice:** Recent list in the tool
**Notes:** History should be visible as part of the tool's main workflow.

### How should users reuse a saved BPM?

| Option | Description | Selected |
|--------|-------------|----------|
| Copy from each row | Each history item has a copy action for its saved BPM. | yes |
| Click row to restore display | Useful, but could blur current tapping vs past result. | |
| Both row restore and copy | Flexible, but more UI to explain/test. | |

**User's choice:** Copy from each row
**Notes:** Avoid conflating saved values with the active tap run.

### Should Phase 2 include deleting history entries?

| Option | Description | Selected |
|--------|-------------|----------|
| Clear all only | One simple cleanup action for the local history. | yes |
| Delete individual rows + clear all | More control, a bit more UI and persistence work. | |
| No delete yet | Simplest, but history can get cluttered. | |

**User's choice:** Clear all only
**Notes:** Individual row deletion is not in Phase 2.

---

## the agent's Discretion

- Exact pause timeout.
- Exact outlier thresholds.
- Exact BPM rounding/display precision.
- Exact visual layout and number of visible recent entries.
- Exact local persistence mechanism for BPM history.

## Deferred Ideas

None.
