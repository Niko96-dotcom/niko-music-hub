---
phase: 19-design-system-foundation
plan: 04
subsystem: ui
tags: [swiftui, controls, appcore]
requires:
  - phase: 19-design-system-foundation
    provides: Size and Colors tokens
provides:
  - 30pt icon buttons with hover tint
  - 7px semantic StatusDot
  - 680pt HubToolLayout width
  - HubCompactChipColors.archive in AppCore
affects: [phase-20, phase-23]
tech-stack:
  added: []
  patterns: [archive chip preset on AppCore type]
key-files:
  created: [Tests/AppCoreTests/HubSharedControlsTests.swift]
  modified:
    - Sources/AppCore/Components/HubIconButton.swift
    - Sources/AppCore/Components/StatusDot.swift
    - Sources/AppCore/Components/HubToolLayout.swift
    - Sources/AppCore/Components/HubCompactChipColors.swift
  deleted: [Sources/FeatureArchiveBrowser/HubCompactChipColors+Archive.swift]
key-decisions:
  - "Archive chip uses HubDesignSystem.Colors.accent, not ArchiveDesignTokens (Phase 20 deletes tokens file)"
requirements-completed: [DS-05, DS-06, DS-07, DS-08]
duration: 15min
completed: 2026-05-31
---

# Phase 19 Plan 04: Shared Controls Summary

**Updated icon button, status dot, tool layout, and merged archive chip colors into AppCore; removed feature extension file.**

## Task Commits

1. **Shared controls + chip merge** — `57ed256` (feat)

## Deviations from Plan

None — plan executed as written.

## Self-Check: PASSED

- HubCompactChipColors+Archive.swift absent: CONFIRMED
- Commit 57ed256: FOUND
