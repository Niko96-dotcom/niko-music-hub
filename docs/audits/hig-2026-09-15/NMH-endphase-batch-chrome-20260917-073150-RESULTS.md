# End-phase Batch Chrome — NMH-099/100/103/106/107/108/109/111

Date: 2026-09-17 Europe/Berlin (Mac local)
Outcome: **8/8 → `verified-no-change`**

| ID | Evidence |
|----|----------|
| 099 | `HelperExecutableValidationTests` + `SettingsLiquidSourceTests` + `AppAppearanceTests`; `persistSettings` on change; validate-before-save; no Save |
| 100 | `ToolPaneCache` + inactive `.accessibilityHidden` / `.allowsHitTesting(false)`; `HubShellChromeSourceTests` |
| 103 | `accessibilityReduceTransparency` / `accessibilityReduceMotion` in glass/material/buttons; `HubControlStateBehaviorTests` duration→0 |
| 106 | `persistenceIssueBanner` above split; composition records issues; non-blocking |
| 107 | `hubDynamicColor` + `AppAppearance` Follow System ⇒ `NSApp.appearance = nil` |
| 108 | `HubLabeledButton` primary/secondary/ghost; minHeight 32 |
| 109 | `HubToolLayout.maxContentWidth == 680` + column modifier |
| 111 | Persistent player labels; board `Open song detail`; `HubDragAffordance` hidden |

`swift test --filter 'HelperExecutableValidationTests|AppAppearanceTests|HubControlStateBehaviorTests|HubToolContentColumnTests|HubShellChromeSourceTests|HubDesignComponentsTests|SettingsLiquidSourceTests|HubSemanticTokenTests|HubSharedControlsTests|HubDragAffordanceTests'` → 0 failures.

Note: first attempt via Linux executor had no Mac access; this run used MBP-von-Niko Shell.
