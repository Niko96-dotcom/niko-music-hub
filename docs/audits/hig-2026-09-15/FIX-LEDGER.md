# FIX-LEDGER — HIG 2026-09-15

Canonical tracked ledger for `hig-audit-fixes`. Exactly 144 item rows. Status values: `pending` | `in-progress` | `implemented-awaiting-runtime` | `blocked` | `fixed` | `verified-no-change` | `preserved` | `skipped-n/a`. Intermediate states do not count as completed.

| NMH id | phase | status | commit | files | evidence | notes/deviations/decisions |
|---|---|---|---|---|---|---|
| NMH-002 | 1 | implemented-awaiting-runtime | 34ec4f60ba8d6512f8d3406fbd5c096303fb9a27 | ProjectVaultConfirmation.swift, SongDetailView.swift, ArchiveBrowserViewModel*.swift, ArchiveNowConfirmationTests, ProjectVaultConfirmationTests | swift build + ArchiveNowConfirmationTests + ProjectVaultConfirmationTests pass; GUI Accept pending | batch-NMH-002-98bd007f; no live GUI |
| NMH-003 | 1 | implemented-awaiting-runtime | 81f228bd92e439bc83bc643555a73f668d49c436 | ProjectVaultConfirmation, ArchiveBoardView, ArchiveBrowserViewModel*, WorkflowDoneArchiveConfirmationTests | swift build + WorkflowDoneArchiveConfirmationTests (6) + related vault tests pass; GUI drag-onto-Done pending | batch-NMH-003-1c7cac75; no live GUI |
| NMH-058 | 1 | implemented-awaiting-runtime | d348a8000fc3cc5b5408f5f7193ff9a4785e0e70 | (see commit) | see nmh-hig-NMH-058-result.md; worker exit 0 | batch-NMH-058-bc6b1749; auto-integrated |
| NMH-001 | 2 | implemented-awaiting-runtime | 00ef78978ba8cafdefc937c6445670136df6f953 | (see commit) | see nmh-hig-NMH-001-result.md; worker exit 0 | batch-NMH-001-2ca7a451; auto-integrated |
| NMH-015 | 2 | implemented-awaiting-runtime | a5524476fcc7da8fc27c87557e3dafb84c649fa2 | (see commit) | see nmh-hig-NMH-015-result.md; worker exit 0 | batch-NMH-015-2859df7f; auto-integrated |
| NMH-012 | 2 | implemented-awaiting-runtime | ca28a36887ea5e3e59abbf88793c87e21507ab63 | (see commit) | see nmh-hig-NMH-012-result.md; worker exit 0 | batch-NMH-012-979513be; auto-integrated |
| NMH-013 | 2 | implemented-awaiting-runtime | bdb58dbb01ef33a78031010dc32e98394dab3880 | (see commit) | see nmh-hig-NMH-013-result.md; worker exit 0 | batch-NMH-013-f246b460; auto-integrated |
| NMH-014 | 2 | implemented-awaiting-runtime | a15adf837fa5354aa66ebe9ddb206161ce09ec80 | (see commit) | see nmh-hig-NMH-014-result.md; worker exit 0 | batch-NMH-014-f7331524; auto-integrated |
| NMH-016 | 2 | implemented-awaiting-runtime | 9980c1f262603d4def5310f30700067b45be6def | (see commit) | see nmh-hig-NMH-016-result.md; worker exit 0 | batch-NMH-016-642359d2; auto-integrated |
| NMH-022 | 2 | implemented-awaiting-runtime | 77a5c1766257a885790b5b57ea4b69771c8260a0 | (see commit) | see nmh-hig-NMH-022-result.md; worker exit 0 | batch-NMH-022-f53cf0cc; auto-integrated |
| NMH-017 | 2 | implemented-awaiting-runtime | 05c51cd4b4017fd23484aadcde8eab3f138f6951 | (see commit) | see nmh-hig-NMH-017-result.md; worker exit 0 | batch-NMH-017-30e84867; auto-integrated |
| NMH-019 | 2 | implemented-awaiting-runtime | cdf5c68fdade7c76aea7364ce8fd8b40aae9a2c1 | (see commit) | see nmh-hig-NMH-019-result.md; worker exit 0 | batch-NMH-019-107b3fb9; auto-integrated |
| NMH-020 | 2 | implemented-awaiting-runtime | a2910379bacd0c078875d1cfc3fdbb27a2f2727f | (see commit) | see nmh-hig-NMH-020-result.md; worker exit 0 | batch-NMH-020-3240bc11; auto-integrated |
| NMH-021 | 2 | implemented-awaiting-runtime | 331a61f7f17f1ad08afeb2bc5c4d3e778c254e8c | (see commit) | see nmh-hig-NMH-021-result.md; worker exit 0 | batch-NMH-021-085f1d54; auto-integrated |
| NMH-033 | 2 | implemented-awaiting-runtime | 44584bf8be7dc80f0907caf2abeca25fc6320857 | (see commit) | see nmh-hig-NMH-033-result.md; worker exit 0 | batch-NMH-033-18c75ce5; auto-integrated |
| NMH-034 | 2 | implemented-awaiting-runtime | 32abdb004833f9f664b47dca3ec31f407beb8099 | (see commit) | see nmh-hig-NMH-034-result.md; worker exit 0 | batch-NMH-034-2d9e6551; auto-integrated |
| NMH-005 | 3 | pending |  |  |  | class=confirmed issue; sev=High |
| NMH-006 | 3 | pending |  |  |  | class=confirmed issue; sev=High |
| NMH-007 | 3 | pending |  |  |  | class=confirmed issue; sev=High |
| NMH-018 | 3 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-029 | 3 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-030 | 3 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-031 | 3 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-032 | 3 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-035 | 3 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-040 | 3 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-045 | 3 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-046 | 3 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-051 | 3 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-080 | 3 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-085 | 3 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-086 | 3 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-088 | 3 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-004 | 4 | pending |  |  |  | class=confirmed issue; sev=High |
| NMH-052 | 4 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-008 | 4 | pending |  |  |  | class=confirmed issue; sev=High |
| NMH-009 | 4 | pending |  |  |  | class=confirmed issue; sev=High |
| NMH-094 | 4 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-063 | 4 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-010 | 4 | pending |  |  |  | class=confirmed issue; sev=High |
| NMH-011 | 4 | pending |  |  |  | class=confirmed issue; sev=High |
| NMH-059 | 4 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-060 | 4 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-062 | 4 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-065 | 4 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-023 | 5 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-024 | 5 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-025 | 5 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-026 | 5 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-028 | 5 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-036 | 5 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-037 | 5 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-038 | 5 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-043 | 5 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-074 | 5 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-079 | 5 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-068 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-069 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-070 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-071 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-072 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-027 | 6 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-073 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-075 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-076 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-077 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-078 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-041 | 6 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-042 | 6 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-081 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-082 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-044 | 6 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-047 | 6 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-049 | 6 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-050 | 6 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-083 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-084 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-087 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-089 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-039 | 6 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-048 | 6 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-053 | 6 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-054 | 6 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-055 | 6 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-056 | 6 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-057 | 6 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-090 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-091 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-092 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-061 | 6 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-064 | 6 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-066 | 6 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-067 | 6 | pending |  |  |  | class=confirmed issue; sev=Medium |
| NMH-093 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-095 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-096 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-097 | 6 | pending |  |  |  | class=confirmed issue; sev=Low |
| NMH-127 | 7 | pending |  |  |  | class=needs verification; sev=Medium |
| NMH-128 | 7 | pending |  |  |  | class=needs verification; sev=Medium |
| NMH-129 | 7 | pending |  |  |  | class=needs verification; sev=Medium |
| NMH-130 | 7 | pending |  |  |  | class=needs verification; sev=Low |
| NMH-131 | 7 | pending |  |  |  | class=needs verification; sev=Medium |
| NMH-132 | 7 | pending |  |  |  | class=needs verification; sev=Low |
| NMH-133 | 7 | pending |  |  |  | class=needs verification; sev=Medium |
| NMH-134 | 7 | pending |  |  |  | class=needs verification; sev=Medium |
| NMH-135 | 7 | pending |  |  |  | class=needs verification; sev=Low |
| NMH-136 | 7 | pending |  |  |  | class=needs verification; sev=Medium |
| NMH-137 | 7 | pending |  |  |  | class=needs verification; sev=Medium |
| NMH-138 | 7 | pending |  |  |  | class=needs verification; sev=— |
| NMH-139 | 7 | pending |  |  |  | class=needs verification; sev=— |
| NMH-140 | 7 | pending |  |  |  | class=needs verification; sev=Low |
| NMH-141 | 7 | pending |  |  |  | class=needs verification; sev=Low / Medium / — |
| NMH-142 | 7 | pending |  |  |  | class=needs verification; sev=— |
| NMH-098 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-099 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-100 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-101 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-102 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-103 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-104 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-105 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-106 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-107 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-108 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-109 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-110 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-111 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-112 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-113 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-114 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-115 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-116 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-117 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-118 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-119 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-120 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-121 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-122 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-123 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-124 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-125 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-126 | 8 | pending |  |  |  | class=passes tested check; sev=— |
| NMH-143 | 8 | pending |  |  |  | class=not applicable; sev=— |
| NMH-144 | 8 | pending |  |  |  | class=not applicable; sev=— |

## Footer

- Baseline main SHA: `55e8cf8f98fe8e4a46d0ac7066c1643070a2f62c`
- Run root: durable directory under Application Support/NikoMusicHub-HIG-Overnight

