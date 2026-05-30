# hub-polish handoff

**Manifest:** `.ai/tasks/hub-polish-waves.json`  
**Status:** All waves **A–G** complete.

## Last session

| Wave | Commit | Notes |
|------|--------|--------|
| F | `0dcff9e` | Inbox cards: filename only, card drag, collapsible tool/inbox sidebars |
| G | `0dcff9e` | `HubGlassChrome` — `glassEffect` on macOS 26+, `.regularMaterial` fallback; shell sidebars + archive header |

## Visual (G)

- **Shell:** tool sidebar + output inbox use `hubGlassChrome()`
- **Archive:** Cubase Archive header block (one tool surface)
- **Older macOS:** material fallback only; no build break at deployment target 14.2

## Gates

`./script/ci.sh` green after F+G.
