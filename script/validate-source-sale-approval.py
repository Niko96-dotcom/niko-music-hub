#!/usr/bin/env python3
"""Validate the legal-owner attestation required for a sale-labeled source export."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


REQUIRED_ATTESTATIONS = (
    "source_rights_transferable",
    "seed_project_rights_transferable",
    "brand_asset_rights_transferable",
    "fixtures_are_synthetic_and_private_data_free",
    "excluded_material_reviewed",
    "written_sale_or_license_terms_exist",
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--approval", required=True)
    parser.add_argument("--commit", required=True)
    args = parser.parse_args()

    path = Path(args.approval)
    if not path.is_file():
        raise SystemExit(f"source-sale approval missing: {path}")
    payload = json.loads(path.read_text(encoding="utf-8"))

    expected = {
        "schema_version": 1,
        "status": "approved",
        "commit": args.commit,
    }
    for key, value in expected.items():
        if payload.get(key) != value:
            raise SystemExit(f"source-sale approval {key} mismatch: {payload.get(key)!r} != {value!r}")

    for key in ("legal_entity", "approved_by"):
        value = payload.get(key)
        if not isinstance(value, str) or not value.strip() or value.strip() == "TODO":
            raise SystemExit(f"source-sale approval needs a real {key}")
    approved_at = payload.get("approved_at_utc", "")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", approved_at):
        raise SystemExit("source-sale approval approved_at_utc must be an ISO-8601 UTC timestamp")

    attestations = payload.get("attestations", {})
    for key in REQUIRED_ATTESTATIONS:
        if attestations.get(key) is not True:
            raise SystemExit(f"source-sale approval attestation '{key}' must be true")

    print(
        "source-sale approval ok: "
        f"commit={args.commit} legal_entity={payload['legal_entity']} approved_by={payload['approved_by']}"
    )


if __name__ == "__main__":
    main()
