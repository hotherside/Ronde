#!/usr/bin/env python3
"""Score opt-in EdgeTAM app XCTest evidence against private references.

The app has already run. This script validates the persisted service/archive
identity and converts its canonical source-timed observations to the shared
benchmark scorer. It does not load Core ML or media and never reads labels while
tracking.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path
from typing import Any, Mapping, Sequence

from python.benchmark import ValidationError, score, validate_reference


MODEL_KEYS = {"image", "attention", "point", "noPoint", "memory"}
SHA256_LENGTH = 64
PTS_TOLERANCE_SECONDS = 0.001


def _normalise_hash(value: Any, field: str) -> str:
    if not isinstance(value, str):
        raise ValidationError(f"{field} must be a SHA-256 string")
    value = value.strip().lower()
    if value.startswith("sha256:"):
        value = value[7:]
    if len(value) != SHA256_LENGTH or any(char not in "0123456789abcdef" for char in value):
        raise ValidationError(f"{field} must contain a 64-character SHA-256 digest")
    return value


def _file_hash(path: Path, field: str) -> str:
    try:
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            while chunk := stream.read(1024 * 1024):
                digest.update(chunk)
        return digest.hexdigest()
    except OSError as error:
        raise ValidationError(f"could not read {field}: {path}") from error


def _load_json(path: Path, kind: str) -> Mapping[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ValidationError(f"could not read {kind} JSON: {path}") from error
    if not isinstance(value, Mapping):
        raise ValidationError(f"{kind} JSON must contain an object")
    return value


def _repo_root() -> Path:
    for parent in Path(__file__).resolve().parents:
        if (parent / "project.yml").is_file() and (parent / "AGENTS.md").is_file():
            return parent
    raise ValidationError("could not determine repository root")


def _require_external(path: Path, repo_root: Path, description: str) -> Path:
    resolved = path.expanduser().resolve()
    try:
        resolved.relative_to(repo_root)
    except ValueError:
        return resolved
    raise ValidationError(f"{description} must be outside the repository")


def _required_int(value: Any, field: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValidationError(f"{field} must be an integer")
    return value


def _finite(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValidationError(f"{field} must be finite")
    result = float(value)
    if not math.isfinite(result):
        raise ValidationError(f"{field} must be finite")
    return result


def _validate_manifest(manifest: Mapping[str, Any]) -> tuple[str, str, dict[str, str]]:
    if manifest.get("schemaVersion") != 1:
        raise ValidationError("model manifest schemaVersion must be 1")
    model_version = manifest.get("modelVersion")
    if not isinstance(model_version, str) or not model_version:
        raise ValidationError("model manifest modelVersion is required")
    constants_hash = _normalise_hash(manifest.get("constantsSHA256"), "model manifest constantsSHA256")
    raw_models = manifest.get("expectedCompiledModelSHA256")
    if not isinstance(raw_models, Mapping) or set(raw_models) != MODEL_KEYS:
        raise ValidationError("model manifest must contain exactly the five service model keys")
    model_hashes = {
        key: _normalise_hash(raw_models[key], f"model manifest expectedCompiledModelSHA256.{key}")
        for key in sorted(MODEL_KEYS)
    }
    return model_version, constants_hash, model_hashes


def _validate_model_identity(
    identity: Mapping[str, Any], manifest: Mapping[str, Any], manifest_path: Path
) -> dict[str, Any]:
    model_version, constants_hash, model_hashes = _validate_manifest(manifest)
    if identity.get("modelVersion") != model_version:
        raise ValidationError("app modelIdentity.modelVersion differs from --model-manifest")
    actual_constants = _normalise_hash(identity.get("constantsSHA256"), "app modelIdentity.constantsSHA256")
    if actual_constants != constants_hash:
        raise ValidationError("app modelIdentity.constantsSHA256 differs from --model-manifest")
    raw_models = identity.get("compiledModelSHA256")
    if not isinstance(raw_models, Mapping) or set(raw_models) != MODEL_KEYS:
        raise ValidationError("app modelIdentity.compiledModelSHA256 must contain exactly five model keys")
    actual_models = {
        key: _normalise_hash(raw_models[key], f"app modelIdentity.compiledModelSHA256.{key}")
        for key in sorted(MODEL_KEYS)
    }
    if actual_models != model_hashes:
        raise ValidationError("app modelIdentity.compiledModelSHA256 differs from --model-manifest")
    actual_manifest = _file_hash(manifest_path, "model manifest")
    identity_manifest = _normalise_hash(identity.get("manifestSHA256"), "app modelIdentity.manifestSHA256")
    if identity_manifest != actual_manifest:
        raise ValidationError("app modelIdentity.manifestSHA256 does not match --model-manifest")
    return {
        "modelVersion": model_version,
        "constantsSHA256": f"sha256:{constants_hash}",
        "compiledModelSHA256": {key: f"sha256:{actual_models[key]}" for key in sorted(MODEL_KEYS)},
        "manifestSHA256": f"sha256:{actual_manifest}",
    }


def _canonical_prediction(
    evidence: Mapping[str, Any], reference: Mapping[str, Any], manifest: Mapping[str, Any], manifest_path: Path
) -> tuple[dict[str, Any], dict[str, Any]]:
    if evidence.get("schemaVersion") != 1:
        raise ValidationError("app evidence schemaVersion must be 1")
    clip_id = evidence.get("clipID")
    if not isinstance(clip_id, str) or not clip_id:
        raise ValidationError("app evidence clipID is required")
    reference_meta, reference_frames = validate_reference(reference)
    if clip_id != reference_meta["clipId"]:
        raise ValidationError("app evidence clipID differs from reference clipId")

    source_hash = _normalise_hash(evidence.get("sourceSHA256"), "app evidence sourceSHA256")
    reference_hash = _normalise_hash(reference_meta["sourceHash"], "reference sourceHash")
    if source_hash != reference_hash or evidence.get("sourceHashVerified") is not True:
        raise ValidationError("app evidence source hash is not verified against the reference")
    width = _required_int(evidence.get("sourceWidth"), "app evidence sourceWidth")
    height = _required_int(evidence.get("sourceHeight"), "app evidence sourceHeight")
    if width != reference_meta["width"] or height != reference_meta["height"]:
        raise ValidationError("app evidence dimensions differ from the reference")

    if evidence.get("outcome") != "completed":
        raise ValidationError("app evidence outcome is not completed")
    if evidence.get("serviceStatus") != "completed":
        raise ValidationError("app evidence serviceStatus is not completed")
    if evidence.get("archiveRoundTripPassed") is not True:
        raise ValidationError("app evidence archiveRoundTripPassed is not true")

    identity = evidence.get("modelIdentity")
    if not isinstance(identity, Mapping):
        raise ValidationError("app evidence modelIdentity is required")
    checked_identity = _validate_model_identity(identity, manifest, manifest_path)

    frame_times = evidence.get("frameTimes")
    source_indices = evidence.get("sourceFrameIndices")
    canonical = evidence.get("canonical")
    if not isinstance(frame_times, list) or not isinstance(source_indices, list) or not isinstance(canonical, list):
        raise ValidationError("app evidence frameTimes, sourceFrameIndices and canonical must be arrays")
    if len(frame_times) != len(source_indices) or not frame_times or not canonical:
        raise ValidationError("app evidence frame arrays must be non-empty and canonical must contain visited records")
    if len(canonical) > len(frame_times):
        raise ValidationError("app evidence canonical records cannot exceed the selected source frames")

    source_frames: dict[int, tuple[float, int]] = {}
    previous_time: float | None = None
    previous_index: int | None = None
    for index, (raw_time, raw_source_index) in enumerate(zip(frame_times, source_indices)):
        timestamp = _finite(raw_time, f"app evidence frameTimes[{index}]")
        source_index = _required_int(raw_source_index, f"app evidence sourceFrameIndices[{index}]")
        if previous_time is not None and timestamp <= previous_time:
            raise ValidationError("app evidence frameTimes must be strictly increasing")
        if previous_index is not None and source_index <= previous_index:
            raise ValidationError("app evidence sourceFrameIndices must be strictly increasing")
        previous_time, previous_index = timestamp, source_index
        source_frames[index] = (timestamp, source_index)

    reference_by_source_index: dict[int, Mapping[str, Any]] = {}
    previous_reference_index: int | None = None
    for index, frame in enumerate(reference.get("frames", [])):
        if not isinstance(frame, Mapping):
            raise ValidationError(f"reference.frames[{index}] must be an object")
        if "sourceFrameIndex" not in frame:
            raise ValidationError("reference frames must include sourceFrameIndex for app evidence scoring")
        source_index = _required_int(frame["sourceFrameIndex"], f"reference.frames[{index}].sourceFrameIndex")
        if source_index in reference_by_source_index:
            raise ValidationError("reference sourceFrameIndex values must be unique")
        if previous_reference_index is not None and source_index <= previous_reference_index:
            raise ValidationError("reference sourceFrameIndex values must be strictly increasing")
        previous_reference_index = source_index
        reference_by_source_index[source_index] = frame

    # The service's frame manifest covers the requested interval, while
    # canonical records stop when propagation terminates. Keep that visited
    # subset source-timed; omitted manifest frames must remain benchmark
    # misses rather than being silently fabricated or dropped.
    predictions: list[dict[str, Any]] = []
    visible_record_count = 0
    gap_count = 0
    seen_interval_indices: set[int] = set()
    previous_interval_index: int | None = None
    for record_index, raw_record in enumerate(canonical):
        if not isinstance(raw_record, Mapping):
            raise ValidationError(f"app evidence canonical[{record_index}] must be an object")
        interval_index = _required_int(raw_record.get("intervalFrameIndex"), f"canonical[{record_index}].intervalFrameIndex")
        if interval_index not in source_frames:
            raise ValidationError(f"canonical[{record_index}] has an invalid intervalFrameIndex")
        if previous_interval_index is not None and interval_index <= previous_interval_index:
            raise ValidationError("app evidence canonical intervalFrameIndex values must be strictly increasing")
        if interval_index in seen_interval_indices:
            raise ValidationError("app evidence canonical intervalFrameIndex values must be unique")
        seen_interval_indices.add(interval_index)
        previous_interval_index = interval_index
        expected_time, expected_source_index = source_frames[interval_index]
        source_index = _required_int(raw_record.get("sourceFrameIndex"), f"canonical[{record_index}].sourceFrameIndex")
        timestamp = _finite(raw_record.get("sourcePTS"), f"canonical[{record_index}].sourcePTS")
        if timestamp < 0:
            raise ValidationError(f"canonical[{record_index}].sourcePTS must not be negative")
        if source_index != expected_source_index or abs(timestamp - expected_time) > 1e-9:
            raise ValidationError(f"canonical[{record_index}] is misaligned with the app source-frame manifest")
        if source_index not in reference_by_source_index:
            raise ValidationError(f"canonical[{record_index}] sourceFrameIndex is absent from the reference")
        reference_time = _finite(reference_by_source_index[source_index].get("timestamp"), f"reference timestamp for source frame {source_index}")
        if abs(timestamp - reference_time) > PTS_TOLERANCE_SECONDS:
            raise ValidationError(f"canonical[{record_index}] PTS differs from reference by more than 1 ms")
        visible = raw_record.get("visible")
        if not isinstance(visible, bool):
            raise ValidationError(f"canonical[{record_index}].visible must be boolean")
        point = raw_record.get("normalisedPoint")
        if visible:
            visible_record_count += 1
            if not isinstance(point, Mapping):
                raise ValidationError(f"visible canonical[{record_index}] is missing normalisedPoint")
            x = _finite(point.get("x"), f"canonical[{record_index}].normalisedPoint.x")
            y = _finite(point.get("y"), f"canonical[{record_index}].normalisedPoint.y")
            if not 0 <= x <= 1 or not 0 <= y <= 1:
                raise ValidationError(f"canonical[{record_index}] normalisedPoint is outside [0,1]")
            predictions.append({"timestamp": timestamp, "x": x, "y": y})
        else:
            gap_count += 1
            if point is not None:
                raise ValidationError(f"non-visible canonical[{record_index}] must retain a nil normalisedPoint")

    if len({item["timestamp"] for item in predictions}) != len(predictions):
        raise ValidationError("visible app predictions contain duplicate source PTS values")
    expected_seed = evidence.get("seedPTS")
    if expected_seed is not None and _finite(expected_seed, "app evidence seedPTS") < 0:
        raise ValidationError("app evidence seedPTS must not be negative")

    prediction = {
        "schemaVersion": "1.0",
        "clipId": clip_id,
        "sourceHash": f"sha256:{source_hash}",
        "width": width,
        "height": height,
        "coordinateOrigin": "top-left",
        "coordinateSpace": "normalized",
        "mode": "assisted",
        "promptCount": 1,
        "correctionCount": 0,
        "frames": predictions,
    }
    verification = {
        "schemaVersion": evidence["schemaVersion"],
        "clipID": clip_id,
        "sourceHashVerified": True,
        "dimensionsVerified": True,
        "timestampToleranceMs": 1.0,
        "canonicalFrameCount": len(canonical),
        "visitedFrameCount": len(canonical),
        "unvisitedFrameCount": len(frame_times) - len(canonical),
        "visiblePredictionCount": visible_record_count,
        "canonicalGapCount": gap_count,
        "modelIdentity": checked_identity,
        "serviceStatus": evidence["serviceStatus"],
        "outcome": evidence["outcome"],
        "archiveRoundTripPassed": True,
    }
    return prediction, verification


def _write_output(path: Path, report: Mapping[str, Any], repo_root: Path) -> None:
    _require_external(path, repo_root, "--output")
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(report, indent=2, sort_keys=True) + "\n"
    path.write_text(payload, encoding="utf-8")


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Score private EdgeTAM app XCTest evidence against private references.")
    parser.add_argument("--evidence", required=True, type=Path, help="one per-clip app XCTest evidence JSON")
    parser.add_argument("--reference", required=True, type=Path, help="private source-timed reference JSON")
    parser.add_argument("--model-manifest", required=True, type=Path, help="packaged edgetam-model-identity.json")
    parser.add_argument("--output", required=True, type=Path, help="external aggregate report JSON path")
    args = parser.parse_args(argv)

    try:
        repo_root = _repo_root()
        evidence_path = _require_external(args.evidence, repo_root, "--evidence")
        reference_path = _require_external(args.reference, repo_root, "--reference")
        manifest_path = _require_external(args.model_manifest, repo_root, "--model-manifest")
        output_path = _require_external(args.output, repo_root, "--output")
        evidence = _load_json(evidence_path, "app evidence")
        reference = _load_json(reference_path, "reference")
        manifest = _load_json(manifest_path, "model manifest")
        prediction, verification = _canonical_prediction(evidence, reference, manifest, manifest_path)
        benchmark = score(reference, prediction, tolerance_ms=1.0, hit_tolerance_px=12.0)
        report = {
            "schemaVersion": "1.0",
            "kind": "edgetam-app-evidence-score",
            "verification": verification,
            "benchmark": benchmark,
        }
        _write_output(output_path, report, repo_root)
        print(json.dumps(report, indent=2, sort_keys=True))
        return 0
    except (ValidationError, OSError) as error:
        print(f"EdgeTAM app scoring error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
