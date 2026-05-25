# Cubase Song Archive Browser Engineering Spec

## 1. Product Summary
Cubase Song Archive Browser is a local-first desktop app that helps a single professional producer browse a Cubase archive as songs instead of raw files. It should let the user find an idea fast, hear the most useful preview immediately, and open the most recently modified relevant `.cpr` without folder hunting. The app is a recall layer on top of an existing Cubase archive, not a generic file manager, spreadsheet, or cloud collaboration tool.

## 2. Core Principles
- Song-first, not file-first
- Preview-first
- Local-first
- Automation-heavy, low-admin
- Virtual organization, not destructive renaming
- Beautiful, not spreadsheet
- One folder = one song
- One card = one song
- Detail page shows the full version list
- Default “Open latest” means most recently modified `.cpr`, not highest version number
- Preview detection uses a confidence system
- Collaborators use manual assignment plus suggestions
- New song creation starts from the app
- Archive scan is opt-in by chosen roots

## 3. Tech Stack
- Electron + Vite
- React 19
- TypeScript
- Zustand
- Tailwind CSS
- Radix UI
- `better-sqlite3`
- Howler.js
- `chokidar`
- FlexSearch

## 4. Information Model

### `songs`
| Field | Type | Notes |
|---|---|---|
| `id` | `TEXT` | Primary key. |
| `folder_path` | `TEXT` | Absolute song folder path; one folder equals one song. |
| `original_folder_name` | `TEXT` | Disk folder name as found on scan. |
| `display_title` | `TEXT` | Resolved UI title for the song. |
| `virtual_title` | `TEXT NULL` | Editable app-owned title override; never renames disk. |
| `aliases` | `TEXT (JSON array)` | Searchable aliases, including technical names if needed for recall. |
| `collaborator_ids` | `TEXT (JSON array)` | Assigned collaborator ids at song level. |
| `song_note` | `TEXT NULL` | Searchable song-level note. |
| `created_at` | `TEXT` | ISO-8601 timestamp for app record creation. |
| `updated_at` | `TEXT` | ISO-8601 timestamp for app record update. |
| `last_cpr_modified_at` | `TEXT NULL` | Newest `.cpr` modification timestamp in the song folder. |
| `last_mixdown_added_at` | `TEXT NULL` | Newest mixdown-like preview candidate add/modify timestamp. |
| `has_stems` | `INTEGER` | Boolean flag for stems detection. |
| `version_count` | `INTEGER` | Count of detected `.cpr` versions for the song. |
| `main_preview_file_id` | `TEXT NULL` | Selected main preview candidate id. |
| `main_cpr_file_id` | `TEXT NULL` | Selected main `.cpr` version id. |
| `preview_selection_mode` | `TEXT` | Enum: `auto` or `manual`. |
| `main_cpr_selection_mode` | `TEXT` | Enum: `auto` or `manual`. |
| `detected_preview_candidates` | `TEXT (JSON array, derived)` | Derived list of preview candidate ids for the song. |
| `cpr_versions` | `TEXT (JSON array, derived)` | Derived list of `.cpr` version ids for the song. |
| `related_signals` | `TEXT (JSON object)` | Scan-derived signals, including future-facing placeholder for “contains material from”. |
| `is_ignored` | `INTEGER` | Boolean flag to hide a song from normal browse flows. |
| `scan_warnings` | `TEXT (JSON array)` | Non-fatal scan warnings for the song. |

### `cpr_versions`
| Field | Type | Notes |
|---|---|---|
| `id` | `TEXT` | Primary key. |
| `song_id` | `TEXT` | Foreign key to `songs.id`. |
| `file_path` | `TEXT` | Absolute `.cpr` file path. |
| `file_name` | `TEXT` | Base file name. |
| `modified_at` | `TEXT` | ISO-8601 modification timestamp. |
| `detected_version_number` | `INTEGER NULL` | Parsed version number when confidence is sufficient. |
| `version_confidence` | `REAL` | Confidence score for parsed version number. |
| `version_note` | `TEXT NULL` | Version-level note. |
| `is_selected_main_cpr` | `INTEGER` | Boolean flag for the current main `.cpr`. |
| `is_ignored` | `INTEGER` | Boolean flag to exclude a specific `.cpr`. |

### `preview_candidates`
| Field | Type | Notes |
|---|---|---|
| `id` | `TEXT` | Primary key. |
| `song_id` | `TEXT` | Foreign key to `songs.id`. |
| `file_path` | `TEXT` | Absolute audio file path. |
| `file_name` | `TEXT` | Base file name. |
| `folder_role` | `TEXT` | Enum: `mixdown`, `stems`, `root`, `other`. |
| `modified_at` | `TEXT` | ISO-8601 modification timestamp. |
| `duration` | `REAL NULL` | Audio duration in seconds. |
| `file_size` | `INTEGER` | File size in bytes. |
| `extension` | `TEXT` | Audio extension such as `wav`, `mp3`, `m4a`, `aiff`, or `flac`. |
| `detected_version_number` | `INTEGER NULL` | Parsed version hint when detectable from filename. |
| `detected_role` | `TEXT` | Enum: `main mix`, `master`, `preview`, `instrumental`, `acapella`, `stems`, `unknown`. |
| `confidence_score` | `REAL` | Aggregate preview ranking score. |
| `confidence_reasons` | `TEXT (JSON array)` | Human-readable ranking reasons. |
| `is_selected_main_preview` | `INTEGER` | Boolean flag for the current main preview. |
| `is_ignored` | `INTEGER` | Boolean flag to exclude a candidate. |

### `collaborators`
| Field | Type | Notes |
|---|---|---|
| `id` | `TEXT` | Primary key. |
| `name` | `TEXT` | Canonical collaborator name. |
| `aliases` | `TEXT (JSON array)` | Alternate names for search and normalization. |
| `manually_confirmed` | `INTEGER` | Boolean flag indicating user confirmation. |
| `detection_count` | `INTEGER` | Count of scan matches behind a suggestion. |
| `source_examples` | `TEXT (JSON array)` | Example filenames and folder names that triggered detection. |

## 5. Screen Inventory
| Screen / View | Description |
|---|---|
| `First-run root selection` | Initial opt-in flow that asks the user to choose one or more root folders to scan; active projects root is required and archive root is optional. |
| `Home browse` | Default editorial browse-first screen with left sidebar, top search bar, and curated shelves for songs and smart categories. |
| `Search results state` | Filtered browse state driven by search queries across titles, aliases, collaborators, notes, folder names, `.cpr` filenames, and preview filenames. |
| `Song detail page` | Single-song view with large waveform hero, collaborators, play/open actions, song note, full `.cpr` version list, preview candidates when relevant, stems/recent exports, and version notes. |
| `New Song modal` | Creation flow that collects song name, collaborators, Cubase template, optional parent root, and optional initial note before creating and opening a new song project. |
| `Collaborator suggestion review UI` | Review interface for repeated detected names, showing count and example matches with explicit yes/no acceptance into the collaborator address book. |

## 6. Feature List by Milestone

### Milestone 1: core archive browser
- choose root
- scan folders
- detect songs
- detect `.cpr`
- detect previews
- play preview
- open latest `.cpr`

### Milestone 2: app metadata layer
- virtual rename
- collaborators
- song notes
- version notes
- choose main preview
- choose main `.cpr`

### Milestone 3: stronger browse/search
- Recently Bounced
- Recent CPR Activity
- Has Stems
- collaborator filter
- search by notes and aliases

### Milestone 4: new song flow
- create folder
- choose collaborators
- choose template
- register song
- open in Cubase

### Milestone 5: polish
- collaborator suggestions
- improved preview confidence
- strong waveform visual system
- loudest-section preview start

## 7. Scanner Behavior
- Scanning is opt-in by user-chosen roots only.
- On first run, the app asks for one or more roots; an active Cubase projects root is the minimum, and an older archive root is optional.
- The scanner assumes each immediate child folder under a selected root is one song.
- All `.cpr` files inside a song folder belong to that song.
- `.bak` files may be detected but are not shown as main versions by default in v1.
- The scanner looks for standard Cubase-ish subfolders when present: `Mixdown`, `Audio`, `Auto Saves`, `Edits`, `Images`, `Track Pictures`, `Stems`, `Exports`, and root-level exports.
- Preview candidate detection scans supported audio exports: `wav`, `mp3`, `m4a`, `aiff` if relevant, and `flac` if encountered.
- Stems detection uses `Stems` folder presence, filename patterns, and many export files consistent with stem export behavior.
- Recency signals include newest `.cpr` modification, newest preview candidate add/modify event, and newest stems-like export.
- The scanner groups versions and preview candidates under the song entity and writes app-owned metadata to the internal database.
- Cadence for v1 includes an initial full scan, incremental updates from file watching, and a manual rescan action.
- The app must not require a full re-ingest on every launch or change.
- The scanner must not depend on deep `.cpr` parsing; it should rely on folder scanning, `.cpr` detection, mixdown detection, stems detection, modification dates, and app-owned metadata.

## 8. Preview Confidence System

### Goal
Each song should resolve to one main preview that the song card can play immediately.

### Positive Signals
- File is inside `Mixdown`
- Filename contains a song-like name
- Filename suggests a full mix: `mixdown`, `mix`, `master`, `preview`, `bounce`
- File is supported audio
- File was modified recently
- Detected version number is higher
- Duration is plausible for a song preview
- Semantic role suggests a main song preview

### Negative Signals
- Filename suggests a non-main mix: `instr`, `instrumental`, `acapella`, `vox only`, `drums only`, `stem`, `stems`, `ref`, `reference`, `test`, `temp`, `old`, `backup`
- File is too short
- File clearly looks like a stem export rather than a song preview

### Role Precedence
- Full mix beats instrumental
- Instrumental beats stems-only if no full mix exists
- Stems should not be selected as the main preview unless there is no better option

### Ranking and Tiebreak Logic
1. Role confidence for full-song preview
2. Location confidence, especially `Mixdown`
3. Semantic filename confidence
4. Most recently modified
5. Version number if reliable
6. Extension preference if still needed

### User Overrides
- Choose main preview manually
- Ignore a candidate
- Revert to auto

### Preview Start
- Product intent favors hearing the best part first, not the dead intro
- V1 may either start at the beginning as a fallback or use a simple loudness/energy-peak heuristic

## 9. Collaborator Detection
- Manual assignment at song level is the truth layer.
- The app includes a reusable collaborator address book for consistency, search/filtering, and new-song creation.
- Scan-based collaborator detection is suggestion-only and must never silently create collaborators.
- Detection logic looks for repeated phrases or name-like tokens across song folder names, `.cpr` filenames, and mixdown filenames.
- Repeated candidate strings should be clustered into likely collaborator suggestions.
- The review UI must show:
  - detected name
  - count
  - example matches
  - add as collaborator: yes or no

## 10. Search Requirements

### Required Query Behaviors
- Show all songs with collaborator X
- Show recent `.cpr` changed files
- Show songs with recently added mixdowns
- Show songs that have stems
- Search song notes
- Search by virtual song name
- Search by original technical name too

### Searchable Fields
- Display title
- Original folder name
- Aliases
- Collaborator names
- Song-level notes
- `.cpr` filenames
- Preview filenames

### Smart Shelves
- Songs
- Recently Bounced
- Recent CPR Activity
- Has Stems
- By Collaborator

### Shelf Definitions
- `Recently Bounced`: songs with newly added or newly modified mixdown-like audio files
- `Recent CPR Activity`: songs whose `.cpr` files were recently modified
- `Has Stems`: songs where stems-like exports are detected

## 11. New Song Creation Flow
1. User clicks `New Song`.
2. Modal asks for song name, collaborators, Cubase template, optional parent root location if needed, and optional initial note.
3. App creates the new song folder.
4. App optionally creates standard subfolders.
5. App creates or prepares the new Cubase project from the selected template.
6. App registers the song immediately in the app.
7. App opens Cubase or opens the created project.

### Recommended V1 Folder Structure
- Song root
- `Mixdown`
- `Stems`
- Optional `Assets`

### Template Constraint
Cubase templates live outside project folders and do not include subfolders or media by themselves, so the flow requires orchestration logic rather than copying a finished project folder wholesale.

## 12. Non-Goals for V1
- Deep `.cpr` parsing as a core dependency
- Cloud sync
- Multi-user collaboration
- Public sharing
- Plugin-state inspection
- Full DAW-agnostic support
- Heavy manual tagging system
- Requiring BPM, key, or genre entry by hand
- Becoming a generic sample or asset manager
