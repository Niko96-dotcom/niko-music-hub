# FIX-LEDGER — HIG 2026-09-15

Canonical tracked ledger for `hig-audit-fixes`. Exactly 144 item rows. Status values: `pending` | `in-progress` | `implemented-awaiting-runtime` | `blocked` | `fixed` | `verified-no-change` | `preserved` | `skipped-n/a`. Intermediate states do not count as completed.

| NMH id | phase | status | commit | files | evidence | notes/deviations/decisions |
|---|---|---|---|---|---|---|
| NMH-002 | 1 | fixed | 34ec4f60ba8d6512f8d3406fbd5c096303fb9a27 | ProjectVaultConfirmation.swift, SongDetailView.swift, ArchiveBrowserViewModel*.swift, ArchiveNowConfirmationTests, ProjectVaultConfirmationTests | gui-unit-promote: swift test --filter ArchiveNowConfirmationTests PASS | batch-NMH-002-98bd007f; no live GUI; gui-unit-promote; gui-unit-promote |
| NMH-003 | 1 | fixed | 81f228bd92e439bc83bc643555a73f668d49c436 | ProjectVaultConfirmation, ArchiveBoardView, ArchiveBrowserViewModel*, WorkflowDoneArchiveConfirmationTests | gui-unit-promote: swift test --filter WorkflowDoneArchiveConfirmationTests PASS | batch-NMH-003-1c7cac75; no live GUI; gui-unit-promote; gui-unit-promote |
| NMH-058 | 1 | fixed | d348a8000fc3cc5b5408f5f7193ff9a4785e0e70 | (see commit) | gui-unit-promote: swift test --filter LiveProjectVaultRuntimeTests PASS | batch-NMH-058-bc6b1749; auto-integrated; gui-unit-promote |
| NMH-001 | 2 | implemented-awaiting-runtime | 00ef78978ba8cafdefc937c6445670136df6f953 | (see commit) | see nmh-hig-NMH-001-result.md; worker exit 0 | batch-NMH-001-2ca7a451; auto-integrated |
| NMH-015 | 2 | implemented-awaiting-runtime | a5524476fcc7da8fc27c87557e3dafb84c649fa2 | (see commit) | see nmh-hig-NMH-015-result.md; worker exit 0 | batch-NMH-015-2859df7f; auto-integrated |
| NMH-012 | 2 | implemented-awaiting-runtime | ca28a36887ea5e3e59abbf88793c87e21507ab63 | (see commit) | see nmh-hig-NMH-012-result.md; worker exit 0 | batch-NMH-012-979513be; auto-integrated |
| NMH-013 | 2 | implemented-awaiting-runtime | bdb58dbb01ef33a78031010dc32e98394dab3880 | (see commit) | see nmh-hig-NMH-013-result.md; worker exit 0 | batch-NMH-013-f246b460; auto-integrated |
| NMH-014 | 2 | implemented-awaiting-runtime | a15adf837fa5354aa66ebe9ddb206161ce09ec80 | (see commit) | see nmh-hig-NMH-014-result.md; worker exit 0 | batch-NMH-014-f7331524; auto-integrated |
| NMH-016 | 2 | fixed | 9980c1f262603d4def5310f30700067b45be6def | (see commit) | gui-unit-promote: swift test --filter MenuBarMenuModelTests PASS | batch-NMH-016-642359d2; auto-integrated; gui-unit-promote |
| NMH-022 | 2 | implemented-awaiting-runtime | 77a5c1766257a885790b5b57ea4b69771c8260a0 | (see commit) | see nmh-hig-NMH-022-result.md; worker exit 0 | batch-NMH-022-f53cf0cc; auto-integrated |
| NMH-017 | 2 | implemented-awaiting-runtime | 05c51cd4b4017fd23484aadcde8eab3f138f6951 | (see commit) | see nmh-hig-NMH-017-result.md; worker exit 0 | batch-NMH-017-30e84867; auto-integrated |
| NMH-019 | 2 | implemented-awaiting-runtime | cdf5c68fdade7c76aea7364ce8fd8b40aae9a2c1 | (see commit) | see nmh-hig-NMH-019-result.md; worker exit 0 | batch-NMH-019-107b3fb9; auto-integrated |
| NMH-020 | 2 | implemented-awaiting-runtime | a2910379bacd0c078875d1cfc3fdbb27a2f2727f | (see commit) | see nmh-hig-NMH-020-result.md; worker exit 0 | batch-NMH-020-3240bc11; auto-integrated |
| NMH-021 | 2 | fixed | 331a61f7f17f1ad08afeb2bc5c4d3e778c254e8c | (see commit) | gui-unit-promote: swift test --filter VaultLaunchAtLoginTests PASS | batch-NMH-021-085f1d54; auto-integrated; gui-unit-promote |
| NMH-033 | 2 | implemented-awaiting-runtime | 44584bf8be7dc80f0907caf2abeca25fc6320857 | (see commit) | see nmh-hig-NMH-033-result.md; worker exit 0 | batch-NMH-033-18c75ce5; auto-integrated |
| NMH-034 | 2 | implemented-awaiting-runtime | 32abdb004833f9f664b47dca3ec31f407beb8099 | (see commit) | see nmh-hig-NMH-034-result.md; worker exit 0 | batch-NMH-034-2d9e6551; auto-integrated |
| NMH-005 | 3 | implemented-awaiting-runtime | e41386256c297ff1512e33135b58aebd88fcde1f | (see commit) | see nmh-hig-NMH-005-result.md; worker exit 0 | batch-NMH-005-cb291108; auto-integrated |
| NMH-006 | 3 | implemented-awaiting-runtime | 9a1c6bc638105b8c29079c88d6fed2486f213a75 | (see commit) | see nmh-hig-NMH-006-result.md; worker exit 0 | batch-NMH-006-8b941415; auto-integrated |
| NMH-007 | 3 | implemented-awaiting-runtime | cc109ed7f6d00085b53057fb4d4cc678441239ed | (see commit) | see nmh-hig-NMH-007-result.md; worker exit 0 | batch-NMH-007-e3074aaf; auto-integrated |
| NMH-018 | 3 | implemented-awaiting-runtime | b5ab86bebf916bc2a95029fd93a636ef0c675d02 | (see commit) | see nmh-hig-NMH-018-result.md; worker exit 0 | batch-NMH-018-69a0daab; auto-integrated |
| NMH-029 | 3 | fixed | 8d2841f1667275aad790e8318a95003e79adec60 | (see commit) | gui-unit-promote: swift test --filter SongCardInteractionTests PASS | batch-NMH-029-4d3e9fb7; auto-integrated; gui-unit-promote |
| NMH-030 | 3 | implemented-awaiting-runtime | 407eae54be77ba430c0f75f23ebd1fba9f15cc14 | (see commit) | see nmh-hig-NMH-030-result.md; worker exit 0 | batch-NMH-030-fb59055d; auto-integrated |
| NMH-031 | 3 | implemented-awaiting-runtime | a6dc15ae86f039841968b276b65817689000ffad | (see commit) | see nmh-hig-NMH-031-result.md; worker exit 0 | batch-NMH-031-b3c84acc; auto-integrated |
| NMH-032 | 3 | implemented-awaiting-runtime | 25ee7c51d9a1f735dd7e54e9c346f3dbfc4ef750 | (see commit) | see nmh-hig-NMH-032-result.md; worker exit 0 | batch-NMH-032-8037b8b9; auto-integrated |
| NMH-035 | 3 | implemented-awaiting-runtime | af603089eaf263d22030c3e29611f6fc807896db | (see commit) | see nmh-hig-NMH-035-result.md; worker exit 0 | batch-NMH-035-6374470a; auto-integrated |
| NMH-040 | 3 | fixed | 64ed96b65e0138b1ad0479c3704b6a9680d44934 | (see commit) | gui-unit-promote: swift test --filter SongCardAccessibilityTests PASS | batch-NMH-040-6f1ccead; auto-integrated; gui-unit-promote |
| NMH-045 | 3 | fixed | 14ab03e14e11a0f055e5f3a6c4867ba066b83780 | (see commit) | gui-unit-promote: swift test --filter ArchiveSearchClearTests PASS | batch-NMH-045-df546bce; auto-integrated; gui-unit-promote |
| NMH-046 | 3 | implemented-awaiting-runtime | 9a1b7edd6b7d3c572e7a6383cee6fe08db500155 | (see commit) | see nmh-hig-NMH-046-result.md; worker exit 0 | batch-NMH-046-c81797d8; auto-integrated |
| NMH-051 | 3 | fixed | da8c61fffd2d2c2d3ea3dd830eb79f3b34e14d39 | (see commit) | gui-unit-promote: swift test --filter ArchiveListSelectionTests PASS | batch-NMH-051-7468024d; auto-integrated; gui-unit-promote |
| NMH-080 | 3 | fixed | bc73dac38c304900145485010419eab9148a0883 | (see commit) | gui-unit-promote: swift test --filter HubMediaSurfaceTests PASS | batch-NMH-080-3ec306b4; auto-integrated; gui-unit-promote |
| NMH-085 | 3 | fixed | 3876a5fa64b64d66766e2314be731f24db2bf19c | (see commit) | gui-unit-promote: swift test --filter SongCardPlayAffordanceTests PASS | batch-NMH-085-79c75817; auto-integrated; gui-unit-promote |
| NMH-086 | 3 | implemented-awaiting-runtime | 631ebf6ddae2ee7f00984cf36e6267f67b03cd6e | (see commit) | see nmh-hig-NMH-086-result.md; worker exit 0 | batch-NMH-086-393ff7ba; auto-integrated |
| NMH-088 | 3 | implemented-awaiting-runtime | 5365b73e81d013cd0b004877e5ad2cc85c7dc943 | (see commit) | see nmh-hig-NMH-088-result.md; worker exit 0 | batch-NMH-088-89e1242e; auto-integrated |
| NMH-004 | 4 | implemented-awaiting-runtime | c5521a5d67e44389a92bb5d4f9961490dd2c2a86 | (see commit) | see nmh-hig-NMH-004-result.md; worker exit 0 | batch-NMH-004-ac322e68; auto-integrated |
| NMH-052 | 4 | fixed | 0f75760937ee0e5ae5171cc58515e8c0a91faa17 | (see commit) | gui-unit-promote: swift test --filter ArchiveRootBookmarkPersistTests PASS | batch-NMH-052-196c3d3f; auto-integrated; gui-unit-promote |
| NMH-008 | 4 | fixed | 772ab1f8bfca98f3ace22e4f33ba2775b63696b5 | (see commit) | gui-unit-promote: swift test --filter ProjectIdentityReviewViewModelTests PASS | batch-NMH-008-0e690624; auto-integrated; gui-unit-promote |
| NMH-009 | 4 | implemented-awaiting-runtime | 6d84540354fb75e4a23fcb24f66cbc6ce318fc3c | (see commit) | see nmh-hig-NMH-009-result.md; worker exit 0 | batch-NMH-009-13ba60bb; auto-integrated |
| NMH-094 | 4 | fixed | c4d1b4644d83894a8abcea403bc729942a0c941e | (see commit) | gui-unit-promote: swift test --filter DownloaderViewModelTests PASS | batch-NMH-094-805063c4; auto-integrated; gui-unit-promote |
| NMH-063 | 4 | fixed | 505b02aeb19f92f35b5d569d8c02c5a06ef25266 | (see commit) | gui-unit-promote: swift test --filter FeatureDownloaderTests PASS | batch-NMH-063-cea9601b; auto-integrated; gui-unit-promote |
| NMH-010 | 4 | fixed | ae095046b3fb02d08d7c847497c6d26eb3930db0 | (see commit) | gui-unit-promote: swift test --filter DownloaderTrustAndErrorTests PASS | batch-NMH-010-59c150c8; auto-integrated; gui-unit-promote |
| NMH-011 | 4 | fixed | e6f9df89b5e1adc418a139c98fcfdebcbe1baf5c | (see commit) | gui-unit-promote: swift test --filter ShellJobStatusCenterTests PASS | batch-NMH-011-bcb4f31e; auto-integrated; gui-unit-promote |
| NMH-059 | 4 | fixed | 2ab7e74b4431ea3776bc844ad667f56900aa1cb0 | (see commit) | gui-unit-promote: swift test --filter FeatureAudioRecorderTests PASS | batch-NMH-059-81a90bb0; auto-integrated; gui-unit-promote |
| NMH-060 | 4 | fixed | b7385e3858764d4818005c89deb20785a5d1c7d6 | (see commit) | gui-unit-promote: swift test --filter BatchAudioConversionUseCaseTests PASS | batch-NMH-060-83afd298; auto-integrated; gui-unit-promote |
| NMH-062 | 4 | implemented-awaiting-runtime | a05db3227241fe1e3d157e1008108dd1d05ab25b | (see commit) | see nmh-hig-NMH-062-result.md; worker exit 0 | batch-NMH-062-c27b31da; auto-integrated |
| NMH-065 | 4 | fixed | 55da39843dfdc2b590db59dd847345ffbddce38a | (see commit) | gui-unit-promote: swift test --filter StemSeparationViewModelTests PASS | batch-NMH-065-6cc15d5b; auto-integrated; gui-unit-promote |
| NMH-023 | 5 | fixed | 98a9b28e63ffc5890991b2d16c85b8f46cb2df48 | (see commit) | gui-unit-promote: swift test --filter HubDesignComponentsTests PASS | batch-NMH-023-9c2919c9; auto-integrated; gui-unit-promote |
| NMH-024 | 5 | implemented-awaiting-runtime | 2f877237a8b298f7d63c902c3f863fa0597475ab | (see commit) | see nmh-hig-NMH-024-result.md; worker exit 0 | batch-NMH-024-0c8aedae; auto-integrated |
| NMH-025 | 5 | implemented-awaiting-runtime | 6752905a99a6f279af245b3ffcb3b8fb2f6a5f4f | (see commit) | see nmh-hig-NMH-025-result.md; worker exit 0 | batch-NMH-025-2f8eb072; auto-integrated |
| NMH-026 | 5 | implemented-awaiting-runtime | 2e596b2e4363e9031ae5e15bc09085eba3cfd80b | (see commit) | see nmh-hig-NMH-026-result.md; worker exit 0 | batch-NMH-026-50cee0a2; auto-integrated |
| NMH-028 | 5 | implemented-awaiting-runtime | e0d1d96c2f1db386d332662dbf22337a36608731 | (see commit) | see nmh-hig-NMH-028-result.md; worker exit 0 | batch-NMH-028-3b0169eb; auto-integrated |
| NMH-036 | 5 | implemented-awaiting-runtime | 9006050290a45ffaf432e9e039b091a1a05d9efc | (see commit) | see nmh-hig-NMH-036-result.md; worker exit 0 | batch-NMH-036-b89bc2c9; auto-integrated |
| NMH-037 | 5 | implemented-awaiting-runtime | 739b17559d5c5b77a2404aff3f09a624d9a6bc67 | (see commit) | see nmh-hig-NMH-037-result.md; worker exit 0 | batch-NMH-037-ee24bb99; auto-integrated |
| NMH-038 | 5 | implemented-awaiting-runtime | 35aaec48b48eefa663298e796856ce9c2e3a8323 | (see commit) | see nmh-hig-NMH-038-result.md; worker exit 0 | batch-NMH-038-f89c456a; auto-integrated |
| NMH-043 | 5 | implemented-awaiting-runtime | dc1f4413ecbaadec3583effc6e0edeb5eb1bce3b | (see commit) | see nmh-hig-NMH-043-result.md; worker exit 0 | batch-NMH-043-da3ecba2; auto-integrated |
| NMH-074 | 5 | implemented-awaiting-runtime | 6484bbeec4073de1d29c6fb89bd21b6387320418 | (see commit) | see nmh-hig-NMH-074-result.md; worker exit 0 | batch-NMH-074-b0f09458; auto-integrated |
| NMH-079 | 5 | implemented-awaiting-runtime | 9b69e68232f12875b46993f33ed99c0bbb0d4b44 | (see commit) | see nmh-hig-NMH-079-result.md; worker exit 0 | batch-NMH-079-a37f50b4; auto-integrated |
| NMH-068 | 6 | implemented-awaiting-runtime | 379c6b48b1bcf8963a01f0a7df119733a2f31332 | (see commit) | see nmh-hig-NMH-068-result.md; worker exit 0 | batch-NMH-068-aec0a771; auto-integrated |
| NMH-069 | 6 | implemented-awaiting-runtime | 6d7995346cb10193e3d48d43063b98c3ffc6ed07 | (see commit) | see nmh-hig-NMH-069-result.md; worker exit 0 | batch-NMH-069-b7befc3d; auto-integrated |
| NMH-070 | 6 | implemented-awaiting-runtime | c77439a39a166ea72c313cf0f5cdfe6bad4bfc90 | (see commit) | see nmh-hig-NMH-070-result.md; worker exit 0 | batch-NMH-070-8545c3f2; auto-integrated |
| NMH-071 | 6 | implemented-awaiting-runtime | 3815a7447716ad52ebd88b215d0320fdff64567f | (see commit) | see nmh-hig-NMH-071-result.md; worker exit 0 | batch-NMH-071-c2f60752; auto-integrated |
| NMH-072 | 6 | implemented-awaiting-runtime | a90bc20bd44ca2e49395e77b84d389451d6683be | (see commit) | see nmh-hig-NMH-072-result.md; worker exit 0 | batch-NMH-072-441de8a7; auto-integrated |
| NMH-027 | 6 | implemented-awaiting-runtime | dbe57466eceda7fd43155e106ed1508809ee2b7b | (see commit) | see nmh-hig-NMH-027-result.md; worker exit 0 | batch-NMH-027-dad1ae5c; auto-integrated |
| NMH-073 | 6 | implemented-awaiting-runtime | 6c9f794b0a8be0b8df1f1ee5860c89b3dc5b315e | (see commit) | see nmh-hig-NMH-073-result.md; worker exit 0 | batch-NMH-073-e6fd12d2; auto-integrated |
| NMH-075 | 6 | implemented-awaiting-runtime | 7565049fdee1b8d13ffbf90aec17cad425ac39ce | (see commit) | see nmh-hig-NMH-075-result.md; worker exit 0 | batch-NMH-075-f5245c30; auto-integrated |
| NMH-076 | 6 | implemented-awaiting-runtime | 065e7e13fa52877dd0bfcd64446c93ad0851acdf | (see commit) | see nmh-hig-NMH-076-result.md; worker exit 0 | batch-NMH-076-78839057; auto-integrated |
| NMH-077 | 6 | implemented-awaiting-runtime | a38deb7a6ed8b9be37cfc440d667c769ad66348c | (see commit) | see nmh-hig-NMH-077-result.md; worker exit 0 | batch-NMH-077-ec9277d0; auto-integrated |
| NMH-078 | 6 | implemented-awaiting-runtime | 973036d20d9dda8ffd538f1db5597dfde59218e0 | (see commit) | see nmh-hig-NMH-078-result.md; worker exit 0 | batch-NMH-078-1e2f5210; auto-integrated |
| NMH-041 | 6 | implemented-awaiting-runtime | f3004c16238d3605e4c05193a0fa3bd12b572191 | (see commit) | see nmh-hig-NMH-041-result.md; worker exit 0 | batch-NMH-041-a4fa23ee; auto-integrated |
| NMH-042 | 6 | implemented-awaiting-runtime | a9a6c62bdab382d447f8ef7c5e9f3fcefa3f69fc | (see commit) | see nmh-hig-NMH-042-result.md; worker exit 0 | batch-NMH-042-f7a0c6b2; auto-integrated |
| NMH-081 | 6 | implemented-awaiting-runtime | 79c435378abd7b6b792d15e82feae917544d4c4d | (see commit) | see nmh-hig-NMH-081-result.md; worker exit 0 | batch-NMH-081-9b7ee65c; auto-integrated |
| NMH-082 | 6 | implemented-awaiting-runtime | 28ce2615cb1cd7035d2b79bf938f9b570f820ba4 | (see commit) | see nmh-hig-NMH-082-result.md; worker exit 0 | batch-NMH-082-b5ab445b; auto-integrated |
| NMH-044 | 6 | implemented-awaiting-runtime | c0284f38cc1ab108d8fc293a195092cd29e9d812 | (see commit) | see nmh-hig-NMH-044-result.md; worker exit 0 | batch-NMH-044-f4551dfb; auto-integrated |
| NMH-047 | 6 | implemented-awaiting-runtime | 295e66469784b737eb3dffad4daa5e52554a1ade | (see commit) | see nmh-hig-NMH-047-result.md; worker exit 0 | batch-NMH-047-5b88493a; auto-integrated |
| NMH-049 | 6 | implemented-awaiting-runtime | 4ad16ebf0bdc353655e11fd6e8869552fe77784a | (see commit) | see nmh-hig-NMH-049-result.md; worker exit 0 | batch-NMH-049-a4a67921; auto-integrated |
| NMH-050 | 6 | implemented-awaiting-runtime | ac18dbdcd31480890f517cdb8c1a8d420801097c | (see commit) | see nmh-hig-NMH-050-result.md; worker exit 0 | batch-NMH-050-c34bf404; auto-integrated |
| NMH-083 | 6 | implemented-awaiting-runtime | 7d68050992b91ad5f3df6e8f14541f3ae6f35cd6 | (see commit) | see nmh-hig-NMH-083-result.md; worker exit 0 | batch-NMH-083-6c70aa6d; auto-integrated |
| NMH-084 | 6 | implemented-awaiting-runtime | c7d4ccbf59ff72777f3cf7b1b44e32b313420468 | (see commit) | see nmh-hig-NMH-084-result.md; worker exit 0 | batch-NMH-084-8913f0fe; auto-integrated |
| NMH-087 | 6 | implemented-awaiting-runtime | 0d32c169280beb939184737ca506577933b4eb3c | (see commit) | see nmh-hig-NMH-087-result.md; worker exit 0 | batch-NMH-087-7876aedc; auto-integrated |
| NMH-089 | 6 | implemented-awaiting-runtime | 9e896c69dd5e5c00722e620c346e06dd0a566a14 | (see commit) | see nmh-hig-NMH-089-result.md; worker exit 0 | batch-NMH-089-c7abe24f; auto-integrated |
| NMH-039 | 6 | implemented-awaiting-runtime | 99d01d9c0cbd1f85489c75a6edaaaf617ed3938c | (see commit) | see nmh-hig-NMH-039-result.md; worker exit 0 | batch-NMH-039-2f3352fd; auto-integrated |
| NMH-048 | 6 | implemented-awaiting-runtime | ea0c9ea9f95b711c97790c2f2cb6608b69ba5239 | (see commit) | see nmh-hig-NMH-048-result.md; worker exit 0 | batch-NMH-048-b46ce416; auto-integrated |
| NMH-053 | 6 | implemented-awaiting-runtime | 1176e9a60cdfeb524c30b6799eefa1b0811e34df | (see commit) | see nmh-hig-NMH-053-result.md; worker exit 0 | batch-NMH-053-0c193548; auto-integrated |
| NMH-054 | 6 | implemented-awaiting-runtime | 63c23b9ef584821969543828d98dfaed9f6e2398 | (see commit) | see nmh-hig-NMH-054-result.md; worker exit 0 | batch-NMH-054-7671acbc; auto-integrated |
| NMH-055 | 6 | implemented-awaiting-runtime | b84c748761f4e89eab1b9f2951163747fa502a83 | (see commit) | see nmh-hig-NMH-055-result.md; worker exit 0 | batch-NMH-055-36735df3; auto-integrated |
| NMH-056 | 6 | implemented-awaiting-runtime | d8f2899ba38452c95b700f40286e29907aea79c9 | (see commit) | see nmh-hig-NMH-056-result.md; worker exit 0 | batch-NMH-056-0c1ce0ac; auto-integrated |
| NMH-057 | 6 | implemented-awaiting-runtime | d35a7ae2f61736733f6c3bdf9e5aca88aca3ad34 | (see commit) | see nmh-hig-NMH-057-result.md; worker exit 0 | batch-NMH-057-8733cf44; auto-integrated |
| NMH-090 | 6 | implemented-awaiting-runtime | a1c873986e973096c3de02b2acadbb9cb2a3a9b8 | (see commit) | see nmh-hig-NMH-090-result.md; worker exit 0 | batch-NMH-090-0769532f; auto-integrated |
| NMH-091 | 6 | implemented-awaiting-runtime | 33e91da09d1c7299c506a7258983f3ebcbede6cd | (see commit) | see nmh-hig-NMH-091-result.md; worker exit 0 | batch-NMH-091-a4a8618b; auto-integrated |
| NMH-092 | 6 | implemented-awaiting-runtime | dc69b025296af4b352ea92a5fdaf7725e9279221 | (see commit) | see nmh-hig-NMH-092-result.md; worker exit 0 | batch-NMH-092-0d07992a; auto-integrated |
| NMH-061 | 6 | implemented-awaiting-runtime | 1b7608cc493614860113b8755c154d160f10d560 | (see commit) | see nmh-hig-NMH-061-result.md; worker exit 0 | batch-NMH-061-02a596df; auto-integrated |
| NMH-064 | 6 | implemented-awaiting-runtime | 5eecb707e1a4917f91a06087be834b73084f09eb | (see commit) | see nmh-hig-NMH-064-result.md; worker exit 0 | batch-NMH-064-b47bd790; auto-integrated |
| NMH-066 | 6 | implemented-awaiting-runtime | 8b0cf17e33305c14b2fe4ec2e9ad2f3b25efffdc | (see commit) | see nmh-hig-NMH-066-result.md; worker exit 0 | batch-NMH-066-c9f15fc5; auto-integrated |
| NMH-067 | 6 | implemented-awaiting-runtime | 9f375d78d1b07ac52936392e19535a30305c3d16 | (see commit) | see nmh-hig-NMH-067-result.md; worker exit 0 | batch-NMH-067-14893256; auto-integrated |
| NMH-093 | 6 | implemented-awaiting-runtime | 8f9be46c221889339325ef2eec8608230444c32c | (see commit) | see nmh-hig-NMH-093-result.md; worker exit 0 | batch-NMH-093-475fd5f9; auto-integrated |
| NMH-095 | 6 | implemented-awaiting-runtime | 81c8338db49e9fc2d4c089f22be1d3c53cae5111 | (see commit) | see nmh-hig-NMH-095-result.md; worker exit 0 | batch-NMH-095-47fbc117; auto-integrated |
| NMH-096 | 6 | implemented-awaiting-runtime | d61219f9ca6aea838a9c23566fc6f0c5ee6fc343 | (see commit) | see nmh-hig-NMH-096-result.md; worker exit 0 | batch-NMH-096-79dcf08f; auto-integrated |
| NMH-097 | 6 | implemented-awaiting-runtime | b623b2fcd29edd17223ac2fbfb04b169cc4f8ea5 | (see commit) | see nmh-hig-NMH-097-result.md; worker exit 0 | batch-NMH-097-94716c5d; auto-integrated |
| NMH-127 | 7 | implemented-awaiting-runtime | f03aa4c1322cf5dfc23dc6d2d2700fdae7c9aa93 | (see commit) | see nmh-hig-NMH-127-result.md; worker exit 0 | batch-NMH-127-77045c76; auto-integrated |
| NMH-128 | 7 | verified-no-change |  | docs/audits/hig-2026-09-15/NMH-128-GUI-ACCEPT.md | GUI Accept 2026-09-16: no overlap (8pt gap) at 1280x820; traffic lights min/zoom PASS; sidebar AXPress PASS; keep titleBarLeadingInset=78 | batch-NMH-128-c760d1ab; auto-integrated; GUI authorized 2026-09-16; gui-accept NMH-128-20260916-184500 |
| NMH-129 | 7 | implemented-awaiting-runtime | c2fde33065b528f322a3c13791d011dc8ecca813 | docs/audits/hig-2026-09-15/NMH-129-GUI-ACCEPT.md | GUI 2026-09-16: Cmd+W Close PASS, Cmd+M PASS, New Window absent PASS; Full Screen FAIL (AXFullScreen false); Undo not confirmed; HubWindowCommandGroup+key monitor added | batch-NMH-129-59bb05e1; auto-integrated; GUI authorized 2026-09-16; gui-accept NMH-129-20260916-211417 |
| NMH-130 | 7 | implemented-awaiting-runtime | a9e083a9566a46831f96b0d3986217aa3b646df9 | (see commit) | see nmh-hig-NMH-130-result.md; worker exit 0 | batch-NMH-130-ff4e3a92; auto-integrated |
| NMH-131 | 7 | implemented-awaiting-runtime | cb46223715cc303b23759fa29629ae6f846d4add | (see commit) | see nmh-hig-NMH-131-result.md; worker exit 0 | batch-NMH-131-8a0f6c52; auto-integrated |
| NMH-132 | 7 | implemented-awaiting-runtime | dc2751f7b340979be286e054c8c7bd92d28350fb | (see commit) | see nmh-hig-NMH-132-result.md; worker exit 0 | batch-NMH-132-abeb713c; auto-integrated |
| NMH-133 | 7 | implemented-awaiting-runtime | ce3b24f378687253a8910e1dd6285724384141c9 | (see commit) | see nmh-hig-NMH-133-result.md; worker exit 0 | batch-NMH-133-afd53f16; auto-integrated |
| NMH-134 | 7 | implemented-awaiting-runtime | 1120075238b2e6d66a80b2418cda47329d5b2d98 | (see commit) | see nmh-hig-NMH-134-result.md; worker exit 0 | batch-NMH-134-f4f52c0c; auto-integrated |
| NMH-135 | 7 | implemented-awaiting-runtime | b68232a42c2c3fce5f397725c37a19e15a5ca6cd | (see commit) | see nmh-hig-NMH-135-result.md; worker exit 0 | batch-NMH-135-a1bbdaae; auto-integrated |
| NMH-136 | 7 | implemented-awaiting-runtime | f582ba1aa50b93b7bdec8314970ce34d4affac91 | (see commit) | see nmh-hig-NMH-136-result.md; worker exit 0 | batch-NMH-136-a8efd48f; auto-integrated |
| NMH-137 | 7 | implemented-awaiting-runtime | 2b665db9a2df583d5450098d5c11d1e5258ea366 | (see commit) | see nmh-hig-NMH-137-result.md; worker exit 0 | batch-NMH-137-f7b9d128; auto-integrated |
| NMH-138 | 7 | implemented-awaiting-runtime | 4d71cb29da7fb9475c6599c671cc152fa90d96e9 | docs/audits/hig-2026-09-15/NMH-138-GUI-ACCEPT.md | GUI 2026-09-16: New Song Esc/Cancel/Create PASS (⇧⌘N); restore Esc pending; Song menu New Song Draft added; live Inbox test dirs deleted | batch-NMH-138-5b82a968; auto-integrated; GUI authorized 2026-09-16; gui-accept NMH-138-20260916-212621 |
| NMH-139 | 7 | implemented-awaiting-runtime |  | docs/audits/hig-2026-09-15/NMH-139-GUI-ACCEPT.md | GUI 2026-09-16: jobs row+footer+card activity exist; Get Local board noticeability not run (needs vault fixture pair) | batch-NMH-139-e6aed559; auto-integrated; GUI authorized 2026-09-16; gui-accept note 2026-09-16 |
| NMH-140 | 7 | implemented-awaiting-runtime | 03c4e962b5611d9395113249bff4bc53b0dd1589 | (see commit) | see nmh-hig-NMH-140-result.md; worker exit 0 | batch-NMH-140-86317f20; auto-integrated |
| NMH-141 | 7 | implemented-awaiting-runtime | be55e1f4dfaacf1044010e2125c70d866bd4ec89 | (see commit) | see nmh-hig-NMH-141-result.md; worker exit 0 | batch-NMH-141-6a25c394; auto-integrated |
| NMH-142 | 7 | implemented-awaiting-runtime | d57af228ee63e2b4a4c0b332c8d6798e38b39870 | (see commit) | see nmh-hig-NMH-142-result.md; worker exit 0 | batch-NMH-142-ab4e493c; auto-integrated |
| NMH-098 | 8 | preserved |  | (see commit) | end-phase preserve; Regression for NMH-001. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-099 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-015 (window). NMH-071 (banner placement). NMH-102 (write guard). Ledger: `preserved` immediate-apply. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-100 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-011, NMH-017, NMH-116. Ledger: `preserved` cache + `accessibilityHidden`. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-101 | 8 | preserved |  | (see commit) | end-phase preserve; Highest-value vault pass. NMH-053 chooser must not weaken the engine. Ledger: `preserved`. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-102 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-095 preview; NMH-141 skip copy. Ledger: `preserved` writers. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-103 | 8 | preserved |  | (see commit) | end-phase preserve; Leftover motion NMH-037. IC NMH-024. Sheen NMH-074. Ledger: `preserved` Reduce Transparency/Motion chrome. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-104 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-016, NMH-121, NMH-132. Ledger: `preserved` extra-as-menu. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-105 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-015 pane move. Ledger: `preserved` fail-closed updates. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-106 | 8 | preserved |  | (see commit) | end-phase preserve; Independent of NMH-004. Ledger: `preserved`; note if the VO trait was added. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-107 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-024 IC variants. Ledger: `preserved` provider. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-108 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-026 press. NMH-066 Stems. Ledger: `preserved` labeled hierarchy. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-109 | 8 | preserved |  | (see commit) | end-phase preserve; Independent of Archive split (NMH-118). Ledger: `preserved` 680 cap. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-110 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-073 counts. Ledger: `preserved` formatter. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-111 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-005, NMH-042, NMH-101, NMH-104. Ledger: `preserved` A11Y-28 surfaces. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-112 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-083, NMH-136, NMH-052. Ledger: `preserved` first-run copy. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-113 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-033, NMH-045, NMH-047. Ledger: `preserved` live search. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-114 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-003 Done confirm, NMH-005 alternatives, NMH-037 leftover motion, NMH-141 cursor. Ledger: `preserved` drag/drop. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-115 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-036 floor. StatusDot is NMH-079 (do not reuse here). Ledger: `preserved` inclusive workflow color. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-116 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-137 unplug NV. NMH-100 cache. Ledger: `preserved` persistent player + capture pause. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-117 | 8 | preserved |  | (see commit) | end-phase preserve; Independent of NMH-134 type scaling. Ledger: `preserved` candidate UI. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-118 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-051 list activation. Ledger: `preserved` 780 split. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-119 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-050, NMH-087. Ledger: `preserved` empty/zero Analytics. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-120 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-009, NMH-044, NMH-110. Ledger: `preserved` cache+background scan. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-121 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-016 extra. Do not default Quit. Ledger: `preserved` quit alert. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-122 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-002, NMH-003, NMH-057. Friends+backup removal still gated. Ledger: `preserved` fail-closed vault paths. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-123 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-007, NMH-029, NMH-035, NMH-063, NMH-096. Ledger: `preserved` BPM pad/clipboard/confirm. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-124 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-059, NMH-064, NMH-081, NMH-126. Ledger: `preserved` recorder meter/timer/banner. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-125 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-030, NMH-061, NMH-063. Do not add informational alerts. Ledger: `preserved` shelf/drop/validation. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-126 | 8 | preserved |  | (see commit) | end-phase preserve; NMH-059 runtime denial. Do not imitate Allow. Ledger: `preserved` purpose strings. | class=passes tested check; sev=—; deferred-sweep 2026-09-16 |
| NMH-143 | 8 | skipped-n/a |  | (see commit) | n/a: Extra uses titled Labels (NMH-104). | class=not applicable; sev=—; deferred-sweep 2026-09-16 |
| NMH-144 | 8 | skipped-n/a |  | (see commit) | n/a: Implement NMH-011 instead. | class=not applicable; sev=—; deferred-sweep 2026-09-16 |

## Footer

- Baseline main SHA: `55e8cf8f98fe8e4a46d0ac7066c1643070a2f62c`
- Run root: durable directory under Application Support/NikoMusicHub-HIG-Overnight

