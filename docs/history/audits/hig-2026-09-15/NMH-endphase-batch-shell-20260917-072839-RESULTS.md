# End-phase Batch Shell — NMH-098/104/105/110/121

Date: 2026-09-17 Europe/Berlin
Outcome: all five → `verified-no-change`

| ID | Evidence |
|----|----------|
| 098 | `AppMenu.swift` + `testCheckForUpdatesIsInTheAppMenu` |
| 104 | `.menuBarExtraStyle(.menu)` + `MenuBarSourceTests` |
| 105 | `UpdatePackagingContractTests` (fail-closed keys / Sparkle isolation) |
| 110 | `HubRelativeTime` + `HubRelativeTimeTests` |
| 121 | Quit alert first button Keep Open; Quit secondary; informative recovery text |

`swift test --filter 'HubRelativeTimeTests|MenuBarMenuModelTests|MenuBarSourceTests|UpdatePackagingContractTests'` → 0 failures.
