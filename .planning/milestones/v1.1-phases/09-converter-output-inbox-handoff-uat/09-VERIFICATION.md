---
phase: "09"
name: "converter-output-inbox-handoff-uat"
status: human_needed
completed: "2026-05-23"
requirements: ["CONV-06", "CONV-07", "HUB-01"]
---

## Phase 9 Verification

### Automated

| Requirement | Evidence |
|-------------|----------|
| HUB-01 | `OutputInboxNotificationTests`; `JSONOutputInboxStore` posts `.outputInboxDidChange`; inspector `onReceive` refreshes |

### Human (CONV-06, CONV-07)

- [ ] Convert real M4A/MP3 in app; verified WAV in output folder.
- [ ] Drag WAV from converter row or inbox into Cubase/Finder.
- [ ] Complete download/recorder job while inbox visible — new row appears without switching tools.

---

## Tests

`scripts/test.sh` — includes `OutputInboxNotificationTests`.
