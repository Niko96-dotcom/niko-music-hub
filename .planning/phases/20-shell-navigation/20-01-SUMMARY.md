---
phase: 20-shell-navigation
plan: 01
subsystem: ui
tags: [swiftui, shell, hub-tool-layout]
requires:
  - phase: 19-design-system-foundation
    provides: HubDesignSystem, HubToolLayout.maxContentWidth 680
provides:
  - hubToolContentColumn() shared centering wrapper
  - CollapsedSidebarRail hover chrome
affects: [21-tool-pages, 22-tool-pages]
tech-stack:
  added: []
  patterns: ["Double-frame centering for tool column in shell"]
key-files:
  created: [Tests/AppCoreTests/HubToolContentColumnTests.swift]
  modified:
    - Sources/AppCore/Components/HubToolLayout.swift
    - Sources/NikoMusicHub/AppShell/AppShellView.swift
    - Sources/NikoMusicHub/NikoMusicHubApp.swift
key-decisions:
  - "Center tools via shell wrapper, not per-feature edits (S-02)"
requirements-completed: [SH-01]
duration: 25min
completed: 2026-05-31
---

# Phase 20 Plan 01: Shell Layout Summary

**Shared `hubToolContentColumn()` centers all tool panes at 680pt; shell rails and window default match Wave 2 spec.**

## Task Commits

1. **Plan commit** — `f46f9b6` (feat)

## Deviations from Plan

None.

## Self-Check: PASSED

- HubToolContentColumnTests.swift: FOUND
- f46f9b6: FOUND
