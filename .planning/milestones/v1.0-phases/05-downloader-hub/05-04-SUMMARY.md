---
phase: "05-downloader-hub"
plan: "05-04"
status: "complete"
wave: "4"
completed: "2026-05-11"
depends_on: ["05-03"]
---

## Summary

Polished trust framing, error language, and legal wording for the Downloader Hub.

### What was built

**DownloaderCopy.swift**
- Centralized all user-facing strings for the downloader
- `toolLabel = "Downloader"` (D-12: not promotional)
- `trustNotice = "Downloads are for material you are allowed to access and save."` (D-15)
- `sourceLabel`, `destinationLabel` for URL/destination display (D-14)
- Error strings: `missingYtDlp`, `unsupportedURL`, `retryableError`, `permanentError`
- Action strings: `download`, `clear`, `showInFinder`

**DownloaderView.swift updates**
- All user-facing strings from `DownloaderCopy` (no inline string literals)
- Tool label uses `DownloaderCopy.toolLabel`
- Trust info shows Source URL and Output folder before download
- Trust notice text visible in trust info section
- Download button is the only start trigger (no auto-start on URL paste)

**DownloaderViewModel.swift updates**
- Status messages use `DownloaderCopy` constants
- Error messages use `DownloaderCopy` for missing yt-dlp and unsupported URL

**DownloaderTrustAndErrorTests.swift**
- Tests verifying all copy strings are present and non-empty
- Tests verifying trust notice, source/destination labels
- Tests verifying tool label is "Downloader" not promotional

### Requirements addressed
- [DL-07] UI clearly scopes downloads to user-authorized material only
- [D-12] Tool labeled "Downloader" — not promotional
- [D-13] Explicit download button required as start trigger
- [D-14] URL and destination shown before download starts
- [D-15] Trust/legal framing visible before download