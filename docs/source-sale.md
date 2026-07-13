# Commercial Source Export

The working repository contains private planning history and development-only tooling. Do not hand the repository checkout to a buyer. Produce a bounded archive from the exact committed tree instead.

## Candidate proof

```bash
./script/export-source-sale.sh --candidate
```

This creates a scanned `CANDIDATE-NOT-FOR-SALE` archive and checksum under `dist/source-sale/`. It proves the export boundary, package manifest, secret/PII checks, license records, SBOM, and file hashes, but it cannot be represented as approved for transfer.

## Approved handoff

1. Start from `docs/source-sale-approval.template.json` outside the repository.
2. Review `SOURCE_PROVENANCE.md`, every brand asset, the seed-project rights, fixtures, exclusions, and the written transfer/license agreement.
3. Set every attestation to `true`, identify the legal entity and approver, use the exact full Git commit, and set `status` to `approved`.
4. Run:

```bash
./script/export-source-sale.sh --approval /absolute/path/to/approved-source-sale.json
```

The exporter refuses tracked changes, validates the attestation against `HEAD`, archives an explicit allowlist, rejects personal paths/credentials/private workflow state, verifies the Swift package manifest, hashes every included file, and creates a basename-only SHA-256 file.

## Buyer build

On a supported Mac with Xcode and Swift 6:

```bash
swift build --product NikoMusicHub
./script/ci.sh
./script/e2e_user_smoke.sh
```

The app itself has no remote Swift package dependency. FFmpeg, yt-dlp, and demucs-mlx are optional, user-supplied tools and are not included in the transfer. See `THIRD_PARTY_NOTICES.md` and `SBOM.spdx.json`.

The owner attestation and technical scanner reduce accidental disclosure and provenance ambiguity; they do not replace a lawyer’s review of the actual sale agreement.
