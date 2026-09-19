#!/usr/bin/env python3
"""Convert one external Swift harness run to the canonical scoring schema.

The Swift runner takes a supplied impact time. Its spatial tracking is automatic,
but the comparison is labelled assisted rather than end-to-end automatic.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from benchmark import ValidationError, validate_prediction


REPOSITORY = Path(__file__).resolve().parents[3]


def external(path: Path) -> Path:
    resolved = path.expanduser().resolve()
    if resolved == REPOSITORY or REPOSITORY in resolved.parents:
        raise ValidationError("Tracker evidence and output must remain outside the repository")
    return resolved


def convert(directory: Path, clip_id: str) -> dict:
    directory = external(directory)
    manifest = json.loads(external(directory / "manifest.json").read_text())
    result = json.loads(external(directory / "result.json").read_text())
    records = [json.loads(line) for line in external(directory / "frames.ndjson").read_text().splitlines() if line.strip()]
    coordinate_contract = "normalised top-left origin; sourceTime is absolute source presentation time in seconds"
    if manifest.get("coordinateSystem") != coordinate_contract or result.get("coordinateSystem") != coordinate_contract:
        raise ValidationError("Expected the Swift harness normalized-top-left coordinate contract")
    video = manifest["sourceVideo"]
    if "uprightWidth" in video and "uprightHeight" in video:
        width, height = video["uprightWidth"], video["uprightHeight"]
    else:
        # Manifest v1 records encoded dimensions and the preferred transform.
        a, b, c, d, _, _ = video["preferredTransform"]
        width = round(abs(a * video["nativeWidth"]) + abs(c * video["nativeHeight"]))
        height = round(abs(b * video["nativeWidth"]) + abs(d * video["nativeHeight"]))

    def point(value: dict) -> dict:
        return {"timestamp": value["sourceTime"], "x": value["normalizedX"], "y": value["normalizedY"]}

    final_points = []
    for value in result["selectedPositions"]:
        sample = point(value)
        # v1 called this confidence, but it repeated the final track confidence.
        if "trackConfidence" in value or "confidence" in value:
            sample["trackConfidence"] = value.get("trackConfidence", value.get("confidence"))
        final_points.append(sample)
    candidates = [{**point(candidate), "detectorConfidence": candidate["confidence"]}
                  for record in records for candidate in record.get("candidates", [])]
    source_hash = manifest["sourceSHA256"]
    payload = {
        "schemaVersion": "1.0", "clipId": clip_id,
        "sourceHash": source_hash if source_hash.startswith("sha256:") else "sha256:" + source_hash,
        "width": width, "height": height,
        "coordinateOrigin": "top-left", "coordinateSpace": "normalized",
        "mode": "assisted", "promptCount": 1, "correctionCount": 0,
        "assistance": {
            "controlledImpactTime": manifest["controlledImpactTime"],
            "spatialPrompts": 0,
            "diagnosticTileOriginsSupplied": bool(manifest["configuration"].get("diagnosticTileOrigins")),
            "interpretation": "Supplied impact time; does not evaluate automatic impact discovery.",
        },
        "configuration": manifest["configuration"],
        "sourceRevision": manifest["sourceRevision"],
        "sourceHashes": manifest["sourceHashes"],
        "modelSHA256": manifest["modelSHA256"],
        "modelHashScope": manifest.get("modelHashScope", "unspecified"),
        "sourceModelBundleSHA256": manifest.get("sourceModelBundleSHA256"),
        "sourceModelWeightSHA256": manifest.get("sourceModelWeightSHA256"),
        "variant": manifest.get("variant"),
        "frames": final_points, "candidates": candidates,
    }
    validate_prediction(payload)
    return payload


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-directory", type=Path, required=True)
    parser.add_argument("--clip-id", required=True, help="Opaque ID matching the reference file")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        destination = external(args.output)
        payload = convert(args.run_directory, args.clip_id)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(payload, indent=2) + "\n")
    except (OSError, ValueError, KeyError, TypeError) as error:
        # Avoid echoing private input values or decoded coordinates in errors.
        parser.exit(2, f"Conversion failed ({type(error).__name__}); verify the external Swift harness schema.\n")
    print(f"Converted {len(payload['frames'])} selected positions and {len(payload['candidates'])} candidates; supplied-impact assistance recorded.")


if __name__ == "__main__":
    main()
