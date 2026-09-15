# Source and Asset Provenance

This inventory is the commercial handoff record for Niko Music Hub. A sale-labeled source export is blocked until the owner supplies an approved exact-commit attestation using `docs/source-sale-approval.template.json`.

| Material | Origin | Included in buyer export | Rights basis to attest |
|---|---|---:|---|
| Swift product source in `Sources/` | Native Swift implementation developed for Niko Music Hub, seeded from the same owner’s OutsideCubaseHub project and ported rather than embedding its prior runtime | Yes | Seller owns or has transferable rights to both the seed and subsequent implementation |
| Swift tests and fixture generators | Developed for Niko Music Hub | Yes | Seller owns or has transferable rights |
| `Fixtures/` Cubase archive data | Synthetic, fixture-first test material generated for this repository; it must not contain a real user archive | Yes | Seller owns the generated fixture content and has verified no private project was copied |
| `Resources/Brand/` | Niko Music Hub application icon and logo assets supplied for this product | Yes | Seller owns or has transferable commercial rights to every exported image and icon |
| Apple frameworks, Swift toolchain, SQLite system library | Platform/toolchain components | No binaries | Used from the supported macOS/Xcode environment under their respective terms |
| Sparkle updater and helpers | Official Sparkle package pinned in `Package.swift` and `Package.resolved` | Package declaration and lockfile; the app build bundles the framework | Upstream MIT License and included third-party notices; the build includes the complete package license in the app resources |
| FFmpeg, yt-dlp, demucs-mlx and models | Optional user-supplied helpers | No | Not part of the transfer; buyer/operator obtains and licenses separately |
| Cubase reference documents and private planning history | Internal product research and execution history | No | Explicitly excluded from the buyer export |
| Ultimate De-Slop tooling | Third-party MIT development tooling | No | Explicitly excluded from the buyer export |
| automation-health visual reference | Design reference only; no runtime or source dependency is included | No | No copied project is included in the buyer export |

The export gate records the exact Git commit and the SHA-256 of the owner attestation. This inventory is evidence scaffolding, not a substitute for the seller’s legal review or written transfer agreement.
