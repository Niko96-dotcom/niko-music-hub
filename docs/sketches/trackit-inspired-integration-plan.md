# TRACKIT-inspired features — analysis & integration plan

Date: 2026-07-11
Source: TRACKIT by Allan Morrow Studios (macOS track/task manager for producers),
seen via Instagram ad + product page research.

## What TRACKIT is

A standalone, offline macOS app where producers manually track their tracks as
kanban cards (Ideas → In Progress → Mixdown → Master → Done/Released). Features:

- **Kanban board** — cards with title, BPM, key, label, progress bar, "N days ago"
- **Checklists** — per-track task lists with reusable templates; completion drives
  the card's progress bar ("track at 80% with two jobs left" as finishing motivation)
- **Analytics** — finish rate, tracks stuck in ideas, stuck 30+ days, tracks
  finished per month, per-stage "where tracks stuck their time" duration bars
- **Momentum/streaks** — day-streak gamification
- **Timeline/planner view** — tracks laid out across weekdays
- **Scenes** — separate spaces for own music / client work / label releases
- Fully manual data entry; no connection to actual project files

## Our structural advantage

TRACKIT only knows what the user types in. Niko Music Hub **scans the real
archive**: every song already has `ProjectVersion` entries (CPR files with
`modifiedAt` dates), preview exports, stems detection, and a mixdown BPM
estimator. That means activity history, "last touched," and work-over-time
analytics can be **derived from disk, retroactively, with zero manual upkeep** —
TRACKIT fundamentally cannot do that.

Already covered here: workflow status (7 states, richer than TRACKIT's 5),
inline status editing on cards, status filters, collaborators, notes, aliases.

## What's worth taking

| TRACKIT feature | Verdict | Why |
|---|---|---|
| Timeline view | **Take — better version** | Derive from CPR `modifiedAt` dates: real work history, whole archive, retroactive |
| Status-change history | **Take (prerequisite)** | Needed for "where songs get stuck"; must start logging now — data only accrues forward |
| Per-song checklists + templates | **Take** | Genuine finishing aid; progress % on cards |
| Analytics panel | **Take (later)** | Finish rate + stuck-detection; part derivable from CPR dates today, part needs history log |
| BPM/key on cards | **Partial** | BPM estimator already exists — surface it; key as optional manual field |
| Kanban board | **Optional** | Sidebar status filters already cover the workflow; a board could be an alternate layout mode later |
| Streaks/momentum | **Skip** | Gamification noise; CPR-derived activity view shows momentum honestly |
| Scenes | **Skip** | Single-producer archive; roots + filters already separate concerns |

## Status (2026-07-11)

- Phase 1 (status history log) — **shipped** (`7fbc10c`)
- Chronological timeline view — built, then **reverted** (`2f1f6e9`): Niko's
  "timeline" idea meant *progress visualization*, not an activity feed. The
  projection code is recoverable from git history if the analytics phase wants it.
- Workflow-stage progress bars on cards + Quiet Songs shelf — **shipped** (`c19fff0`)
- Kanban board view (No Status triage column + 7 stage columns, drag to change
  status, click to open detail) — **shipped** (`fc38f15`). This is what Niko
  actually meant by "timeline/board": the TRACKIT screenshots' layout.
- Next: Phase 3 checklists (upgrade the stage bar to checklist-driven %), Phase 4 analytics

## Phased plan

### Phase 1 — Status history log (small, do first)
The only time-sensitive piece: every day without it is analytics data lost.
- New SQLite table `song_status_history(song_id, from_status, to_status, changed_at)`
- Append a row wherever `workflowStatus` is written (card inline menu, detail
  view, metadata editor)
- No UI yet

### Phase 2 — Archive timeline ("the archive as a timeline")
Zero new data required; built entirely from existing scan results.
- New view mode next to the current browse layout
- Vertical timeline grouped by month/year; each song appears at its activity
  dates (CPR `modifiedAt`, preview export dates)
- Song swimlane detail: dots per CPR version → visually shows bursts of work,
  long gaps, abandoned ideas
- Filters (status, collaborator, root) reuse the existing sidebar filter model
- Nice-to-have: "quiet songs" shelf — in-progress status but no CPR touched in
  30+ days (TRACKIT's "stuck 30 days" but grounded in real file activity)

### Phase 3 — Checklists
- `SongChecklist` in SQLite (app-owned, never writes into archive folders —
  consistent with the read-only-archive policy)
- Reusable templates (e.g. "Mixdown checklist", "Release checklist")
- Progress bar on song cards fed by checklist completion
- Checklist section in `SongDetailView`

### Phase 4 — Analytics panel
- Per-stage dwell time from the Phase 1 history log
- Songs touched / finished per month from CPR dates (works retroactively)
- Finish rate, stuck counts, oldest untouched in-progress songs
- Candidate location: extend `ArchiveIntelligencePanelView` or a sibling panel

### Parallel small win
- Show estimated BPM (existing `MixdownBPMEstimator`) on song cards/detail;
  add optional manual key field to `SongUserMetadata`

## Sources
- https://allanmorrowstudios.com/trance-music/trackit-track-task-manager-tracker/
- Instagram ad @am_studios_trance_tutorials (screenshots, 2026-07-11)
