# Decision: Shell chrome is the Codex sidebar material, measured — not Liquid Glass

**Status:** Accepted  
**Date:** 2026-09-18  
**Deciders:** Niko Music Hub owner + implementation  
**Scope:** Main window chrome (tools sidebar, tool inspector, Output Inbox, title row), 1.6.0

## Context

The owner wants the main window to read like the Codex desktop app: quiet
neutral chrome, a sidebar you can sense the desktop through, no separate title
bar. Several passes this morning tuned opacities and tints on
`glassEffect(.regular)` and never converged: the rail's tone swung with the
wallpaper, windows behind it stayed legible ("see-through sidebar"), and every
veil that pinned the tone also killed the colour bleed the owner liked.

## What was measured (same screen, both apps, both appearances)

- Codex sidebar over a dark window: rgb(51); over a light window: rgb(77);
  over a red sheet: rgb(249,218,215) light / rgb(82,48,46) dark. Content
  column constant: rgb(45,45,43) dark, rgb(249,250,247) light.
- That signature — colour passes through, shapes never do, tone follows the
  backdrop — is AppKit `NSVisualEffectView` `.sidebar` blended `.behindWindow`.
- Codex has no full-width title strip; the sidebar and content columns run to
  the window top, with the lights and title controls ~23pt below the edge.
- Selection pill: −10 on the rail in light, +15 in dark. Rows pitch at 31pt;
  glyphs are thin ~16pt outlines; section captions are body-size regular grey.

## Decision

1. Every chrome rail is one bare `HubVisualEffectView(.sidebar, .behindWindow)`
   (`HubGlassBackdrop`), on every macOS version, with **nothing painted over
   it**. Guard tests forbid `.glassEffect(`, gradients and white veils in
   `HubMaterial.swift`. Verified with the same red sheet behind our app:
   rgb(222,201,197) light / rgb(80,35,35) dark.
2. No title strip: each column reserves a 44pt title row inside its own
   material; nested rails extend through it via `hubTitleRowInset`; the
   configurator re-centres the traffic lights on `titleBarAxisY` using the
   titlebar view's own coordinates; launch first responder is cleared.
3. The dark neutral scale is Codex's warm neutral (canvas 45/45/43, sidebar
   51/52/49, surface 55, raised 70, separator 66). `Palette.selection` is a
   translucent neutral (black .055 / white .09) so the pill keeps its step over
   whatever the rail shows.
4. Sidebar rhythm: 30pt rows (32 pitch), monochrome 15pt light glyphs,
   body-size tertiary captions with Codex air; the inspector mirrors it
   (measured keylines 120/144 and 194/218 on both rails).

## Rejected

- `glassEffect(.regular)` bare or tinted (lens: shapes legible, tone unstable).
- Vibrancy + calibrated veil (pins the tone but removes the colour bleed —
  the red-sheet test showed rgb(213,213,211) where Codex bleeds).
- Glass + 0.6 sidebar-tone veil "middle ground" (same failure).

## Consequences

The rail tone is intentionally not a fixed number; design tokens that sit on
the rail (pill, captions, hover) are translucent steps. Rules live in
`docs/design-contract.md` §1, §1.1, §1.2 and are enforced by
`HubSurfaceTests`, `HubSemanticTokenTests`, `HubDesignContractSourceTests`,
`HubShellChromeSourceTests` and `ToolSidebarSelectionTests`.
