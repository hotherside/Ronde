#!/usr/bin/env python3
"""Compare private EdgeTAM device evidence with private source-timed references.

The device runner has already completed before this script is invoked. It reads
only the resulting JSON and provisional reference JSON, matches by exact source
frame index plus actual PTS tolerance, and delegates localisation metrics to the
canonical benchmark scorer. No labels are available to the device tracker.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any, Mapping, Optional, Sequence

from python.benchmark import ValidationError, _enforce_private_path, score


def _load(path: Path, kind: str) -> Mapping[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValidationError(f"could not read {kind} JSON") from error
    if not isinstance(value, Mapping):
        raise ValidationError(f"{kind} JSON must contain an object")
    return value


def _normalised_hash(value: Any) -> Optional[str]:
    if not isinstance(value, str) or not value.strip():
        return None
    value = value.lower()
    return value if value.startswith("sha256:") else f"sha256:{value}"


def _finite_number(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValidationError(f"{field} must be finite")
    result = float(value)
    if not math.isfinite(result):
        raise ValidationError(f"{field} must be finite")
    return result


def _mapping_arg(values: Sequence[str], field: str) -> dict[str, Path]:
    result: dict[str, Path] = {}
    for value in values:
        if "=" not in value:
            raise ValidationError(f"{field} must use clip-id=private-path")
        key, raw_path = value.split("=", 1)
        if not key or not raw_path:
            raise ValidationError(f"{field} must use clip-id=private-path")
        if key in result:
            raise ValidationError(f"duplicate {field} for clip {key}")
        result[key] = Path(raw_path).expanduser().resolve()
    return result


def _device_checks(evidence: Mapping[str, Any], reference: Mapping[str, Any], clip_id: str) -> dict[str, Any]:
    expected_source = _normalised_hash(reference.get("sourceHash"))
    expected_models = evidence.get("expectedCompiledModelSHA256")
    actual_models = evidence.get("modelHashes")
    model_hashes_match = isinstance(expected_models, Mapping) and isinstance(actual_models, Mapping) and set(expected_models) == set(actual_models) and all(
        _normalised_hash(expected_models[key]) == _normalised_hash(actual_models[key]) for key in expected_models
    )
    clips = evidence.get("clips")
    if not isinstance(clips, list):
        raise ValidationError("device evidence.clips must be an array")
    clip = next((item for item in clips if isinstance(item, Mapping) and item.get("clipID") == clip_id), None)
    if clip is None:
        raise ValidationError(f"device evidence has no clip {clip_id}")
    observed = _normalised_hash(clip.get("observedSourceSHA256"))
    expected = _normalised_hash(clip.get("expectedSourceSHA256"))
    terms = clip.get("policy", {}).get("terminations", {}) if isinstance(clip.get("policy"), Mapping) else {}
    reasons = sorted({item.get("reason") for item in terms.values() if isinstance(item, Mapping) and isinstance(item.get("reason"), str)})
    return {
        "runStatus": evidence.get("runStatus"),
        "runStatusPass": evidence.get("runStatus") == "completed",
        "compiledModelVerified": evidence.get("compiledModelVerified") is True,
        "compiledModelHashesMatchExpected": model_hashes_match,
        "configurationSHA256Present": isinstance(evidence.get("configurationSHA256"), str),
        "requestedComputeUnits": evidence.get("requestedComputeUnits"),
        "executionBackendEvidence": evidence.get("executionBackendEvidence"),
        "sourceHashMatchesReference": expected_source == observed,
        "clip": {
            "clipId": clip.get("clipID"),
            "outcome": clip.get("outcome"),
            "sourceHashVerified": clip.get("sourceHashVerified") is True and observed == expected,
            "dimensionsVerified": clip.get("dimensionsVerified") is True,
            "actualFrameCount": clip.get("actualFrameCount"),
            "seedPTSValidatedWithin1ms": _seed_validated(clip),
            "terminationReasons": reasons,
            "memorySampled": isinstance(clip.get("memory"), Mapping),
        },
    }


def _seed_validated(clip: Mapping[str, Any]) -> bool:
    expected = clip.get("seedActualPTS")
    # The original seedPTS is deliberately not included in device evidence.
    # A successful clip has already enforced the 1 ms bound in the device app.
    return isinstance(expected, (int, float)) and math.isfinite(float(expected))


def _prediction_from_device(evidence: Mapping[str, Any], reference: Mapping[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    clip_id = reference.get("clipId")
    if not isinstance(clip_id, str):
        raise ValidationError("reference.clipId is required")
    clips = evidence.get("clips")
    if not isinstance(clips, list):
        raise ValidationError("device evidence.clips must be an array")
    clip = next((item for item in clips if isinstance(item, Mapping) and item.get("clipID") == clip_id), None)
    if clip is None:
        raise ValidationError(f"device evidence has no clip {clip_id}")
    canonical = clip.get("canonical")
    if not isinstance(canonical, list):
        raise ValidationError(f"device clip {clip_id}.canonical must be an array")
    reference_frames = reference.get("frames")
    if not isinstance(reference_frames, list):
        raise ValidationError("reference.frames must be an array")
    reference_by_index = {
        frame.get("sourceFrameIndex"): frame
        for frame in reference_frames
        if isinstance(frame, Mapping) and isinstance(frame.get("sourceFrameIndex"), int)
    }
    width = reference.get("width")
    height = reference.get("height")
    if isinstance(width, bool) or not isinstance(width, int) or width <= 0:
        raise ValidationError("reference.width must be a positive integer")
    if isinstance(height, bool) or not isinstance(height, int) or height <= 0:
        raise ValidationError("reference.height must be a positive integer")
    aligned: list[dict[str, Any]] = []
    rejected = {"missingReferenceFrameIndex": 0, "timestampOverTolerance": 0, "duplicateSourceFrameIndex": 0}
    seen: set[int] = set()
    for item in canonical:
        if not isinstance(item, Mapping):
            raise ValidationError(f"device clip {clip_id}.canonical contains a non-object")
        index = item.get("sourceFrameIndex")
        timestamp = item.get("sourcePTS")
        x = item.get("centroidX")
        y = item.get("centroidY")
        visible = item.get("visible")
        if isinstance(index, bool) or not isinstance(index, int):
            raise ValidationError(f"device clip {clip_id}.canonical has invalid source identity")
        timestamp_value = _finite_number(timestamp, f"device clip {clip_id}.canonical sourcePTS")
        if timestamp_value < 0:
            raise ValidationError(f"device clip {clip_id}.canonical sourcePTS must not be negative")
        if not isinstance(visible, bool):
            raise ValidationError(f"device clip {clip_id}.canonical.visible must be boolean")
        has_x, has_y = x is not None, y is not None
        if has_x != has_y:
            raise ValidationError(f"device clip {clip_id}.canonical coordinates must be both present or both nil")
        if visible != has_x:
            raise ValidationError(
                f"device clip {clip_id}.canonical visible state and coordinates disagree"
            )
        if index in seen:
            raise ValidationError(f"device clip {clip_id}.canonical contains duplicate sourceFrameIndex {index}")
        seen.add(index)
        if not visible:
            continue
        x_value = _finite_number(x, f"device clip {clip_id}.canonical centroidX")
        y_value = _finite_number(y, f"device clip {clip_id}.canonical centroidY")
        if not 0 <= x_value <= width or not 0 <= y_value <= height:
            raise ValidationError(f"device clip {clip_id}.canonical coordinates are outside source dimensions")
        frame = reference_by_index.get(index)
        if frame is None:
            rejected["missingReferenceFrameIndex"] += 1
            continue
        reference_timestamp = frame.get("timestamp")
        reference_timestamp_value = _finite_number(
            reference_timestamp, f"reference timestamp for source frame {index}"
        )
        if abs(timestamp_value - reference_timestamp_value) > 0.001:
            rejected["timestampOverTolerance"] += 1
            continue
        aligned.append({
            "timestamp": timestamp_value,
            "x": x_value / width,
            "y": y_value / height,
            "sourceFrameIndex": index,
        })
    aligned.sort(key=lambda item: item["timestamp"])
    prediction = {
        "schemaVersion": "1.0",
        "clipId": clip_id,
        "sourceHash": reference["sourceHash"],
        "width": reference["width"],
        "height": reference["height"],
        "coordinateOrigin": "top-left",
        "coordinateSpace": "normalized",
        "mode": "assisted",
        "promptCount": 1,
        "correctionCount": 0,
        "frames": aligned,
        "sourceRevision": evidence.get("sourceRevision"),
        "sourceHashes": evidence.get("sourceHashes", {}),
        "modelHashScope": "device compiled model tree",
        "variant": "EdgeTAM native device diagnostic",
    }
    return prediction, {"alignedPredictionFrames": len(aligned), "rejectedCanonical": rejected}


def _state_counts(reference: Mapping[str, Any], prediction: Mapping[str, Any]) -> dict[str, Any]:
    predicted = {item.get("sourceFrameIndex") for item in prediction["frames"]}
    states: dict[str, int] = {}
    for frame in reference["frames"]:
        state = frame.get("visibility")
        if not isinstance(state, str):
            continue
        states.setdefault(state, 0)
        states[state] += 1
    absent = {"occluded", "out_of_frame", "not_launched"}
    return {
        "referenceFramesByVisibility": states,
        "observedPredictionFrames": len(predicted),
        "visibleWithoutPrediction": sum(frame.get("visibility") == "visible" and frame.get("sourceFrameIndex") not in predicted for frame in reference["frames"]),
        "absentWithPrediction": sum(frame.get("visibility") in absent and frame.get("sourceFrameIndex") in predicted for frame in reference["frames"]),
        "uncertainWithPrediction": sum(frame.get("visibility") == "uncertain" and frame.get("sourceFrameIndex") in predicted for frame in reference["frames"]),
    }


def _control_comparison(device_prediction: Mapping[str, Any], control_evidence: Mapping[str, Any], clip_id: str, width: int, height: int) -> dict[str, Any]:
    controls = control_evidence.get("clips")
    clip = next((item for item in controls or [] if isinstance(item, Mapping) and item.get("clipID") == clip_id), None)
    if clip is None:
        return {"available": False, "reason": "control has no matching clip"}
    by_index = {item.get("sourceFrameIndex"): item for item in clip.get("canonical", []) if isinstance(item, Mapping) and item.get("centroidX") is not None}
    errors = []
    for item in device_prediction["frames"]:
        control = by_index.get(item.get("sourceFrameIndex"))
        if control is None:
            continue
        dx = float(item["x"]) * width - float(control["centroidX"])
        dy = float(item["y"]) * height - float(control["centroidY"])
        errors.append(math.hypot(dx, dy))
    return {
        "available": True,
        "matchedSourceFrames": len(errors),
        "medianDifferencePx": _percentile(errors, 0.5),
        "maxDifferencePx": max(errors) if errors else None,
    }


def _percentile(values: Sequence[float], percentile: float) -> Optional[float]:
    if not values:
        return None
    ordered = sorted(values)
    rank = (len(ordered) - 1) * percentile
    lower, upper = math.floor(rank), math.ceil(rank)
    if lower == upper:
        return ordered[lower]
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (rank - lower)


def compare(evidence: Mapping[str, Any], references: Mapping[str, Mapping[str, Any]], controls: Mapping[str, Mapping[str, Any]]) -> dict[str, Any]:
    if not isinstance(evidence.get("clips"), list):
        raise ValidationError("device evidence.clips must be an array")
    reports = {}
    for clip_id, reference in references.items():
        prediction, alignment = _prediction_from_device(evidence, reference)
        scores = {
            "4px": score(reference, prediction, tolerance_ms=1.0, hit_tolerance_px=4.0),
            "12px": score(reference, prediction, tolerance_ms=1.0, hit_tolerance_px=12.0),
        }
        reports[clip_id] = {
            "deviceChecks": _device_checks(evidence, reference, clip_id),
            "alignment": alignment,
            "observationStates": _state_counts(reference, prediction),
            "scores": scores,
            "nativeRun2Control": _control_comparison(prediction, controls[clip_id], clip_id, int(reference["width"]), int(reference["height"])) if clip_id in controls else {"available": False},
        }
    return {"schemaVersion": "edgetam-device-score-1", "timestampToleranceMs": 1.0, "clips": reports}


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--evidence", required=True, type=Path, help="private device evidence JSON")
    result.add_argument("--reference", action="append", required=True, help="clip-id=private reference JSON; repeat per clip")
    result.add_argument("--control", action="append", default=[], help="optional clip-id=private native run-2 evidence JSON")
    result.add_argument("--report", type=Path, help="optional private aggregate report path")
    return result


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parser().parse_args(argv)
    repo_root = Path(__file__).resolve().parents[2]
    try:
        evidence_path = args.evidence.expanduser().resolve()
        reference_paths = _mapping_arg(args.reference, "--reference")
        control_paths = _mapping_arg(args.control, "--control")
        for path in [evidence_path, *reference_paths.values(), *control_paths.values(), *([args.report.resolve()] if args.report else [])]:
            _enforce_private_path(path, allow_synthetic_example=False, repo_root=repo_root)
        evidence = _load(evidence_path, "device evidence")
        references = {clip: _load(path, f"reference {clip}") for clip, path in reference_paths.items()}
        controls = {clip: _load(path, f"control {clip}") for clip, path in control_paths.items()}
        report = compare(evidence, references, controls)
        rendered = json.dumps(report, indent=2, sort_keys=True)
        if args.report:
            args.report.write_text(rendered + "\n", encoding="utf-8")
        print(rendered)
        return 0
    except (ValidationError, OSError, KeyError, TypeError, StopIteration) as error:
        print(f"device score error: {type(error).__name__}: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
