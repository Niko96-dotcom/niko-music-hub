# Phase 23: Archive Browse & Sidebar - Context

**Gathered:** 2026-05-31
**Mode:** Smart discuss (autonomous — auto-accepted)

<domain>
Archive sidebar toolbar, horizontal shelf/sort/filter chips, search field, tighter song cards. Token-aligned archive browse surfaces. Song detail restructuring deferred to Phase 24.

</domain>

<decisions>
## Implementation Decisions

- Toolbar: song count badge, scan + plus menu (no ellipsis).
- Shelf chips: short titles in horizontal `ScrollView`.
- Sort: menu chip with current mode title.
- Filters: existing `HubIconButton.archiveBrowseFilter` in same strip.
- Song cards: 14pt title, warning triangle icon, padding 10, list spacing 6.
- Search: prompt-only field, 34px min height.

</decisions>
