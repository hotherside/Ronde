#!/usr/bin/env python3
"""Score a source-timed ball track against explicit, provenance-aware labels.

The scorer intentionally stays independent of the iOS implementation.  It uses
only source PTS values supplied in the JSON and never creates an interpolated
point between two observations.
"""

from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from array import array
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple


SCHEMA_VERSION = "1.0"
VISIBILITIES = {"visible", "occluded", "out_of_frame", "uncertain", "not_launched"}
ABSENT_VISIBILITIES = {"occluded", "out_of_frame", "not_launched"}
REVIEW_STATUSES = {"human-verified", "agent-reviewed", "proposal", "unreviewed"}
REVIEWED_STATUSES = {"human-verified", "agent-reviewed"}
MODES = {"automatic", "assisted"}

_PROVENANCE_SCALAR_KEYS = {
    "sourceRevision",
    "modelSHA256",
    "modelHashScope",
    "sourceModelBundleSHA256",
    "sourceModelWeightSHA256",
    "variant",
    "model",
    "licence",
    "replayCodeRevision",
    "replayCodeSHA256",
    "replayCodeHash",
    "adapterCodeRevision",
    "adapterCodeSHA256",
    "adapterCodeHash",
    "checkpointIdentifier",
    "checkpointSHA256",
    "checkpoint_sha256",
    "checkpointHash",
    "upstreamCommit",
    "upstream_commit",
}
_PROVENANCE_MAPPING_KEYS = {"sourceHashes", "replay", "adapter", "checkpoint"}
_IDENTIFIER_KEYS = {
    "algorithm",
    "name",
    "model",
    "variant",
    "identifier",
    "revision",
    "codeRevision",
    "codeSHA256",
    "codeHash",
    "checkpointIdentifier",
    "checkpointSHA256",
    "checkpoint_sha256",
    "checkpointHash",
    "candidatePoolSHA256",
    "poolManifestSHA256",
    "configurationSHA256",
    "upstreamCommit",
    "upstream_commit",
    "sha256",
    "hash",
}


class ValidationError(ValueError):
    """Raised when an input does not conform to the benchmark schema."""


@dataclass(frozen=True)
class Frame:
    index: int
    timestamp: float
    x: Optional[float]
    y: Optional[float]
    visibility: str
    review_status: str
    uncertainty_px: Optional[float]
    candidate_eligible: bool


@dataclass(frozen=True)
class Point:
    index: int
    timestamp: float
    x: float
    y: float


@dataclass(frozen=True)
class PointGroup:
    index: int
    timestamp: float
    points: Tuple[Point, ...]


def _finite_number(value: Any, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValidationError(f"{field} must be a finite number")
    result = float(value)
    if not math.isfinite(result):
        raise ValidationError(f"{field} must be a finite number")
    return result


def _optional_finite_number(value: Any, field: str) -> Optional[float]:
    if value is None:
        return None
    return _finite_number(value, field)


def _required_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValidationError(f"{field} must be a non-empty string")
    return value


def _metadata(payload: Mapping[str, Any], kind: str) -> Dict[str, Any]:
    if payload.get("schemaVersion") != SCHEMA_VERSION:
        raise ValidationError(f"{kind}.schemaVersion must be {SCHEMA_VERSION!r}")
    clip_id = _required_string(payload.get("clipId"), f"{kind}.clipId")
    source_hash = _required_string(payload.get("sourceHash"), f"{kind}.sourceHash")
    if not source_hash.startswith("sha256:"):
        raise ValidationError(f"{kind}.sourceHash must use the sha256: prefix")
    width = _finite_number(payload.get("width"), f"{kind}.width")
    height = _finite_number(payload.get("height"), f"{kind}.height")
    if width <= 0 or height <= 0 or width != int(width) or height != int(height):
        raise ValidationError(f"{kind}.width and height must be positive integers")
    if payload.get("coordinateOrigin") != "top-left":
        raise ValidationError(f"{kind}.coordinateOrigin must be 'top-left'")
    if payload.get("coordinateSpace") != "normalized":
        raise ValidationError(f"{kind}.coordinateSpace must be 'normalized'")
    return {
        "clipId": clip_id,
        "sourceHash": source_hash,
        "width": int(width),
        "height": int(height),
        "coordinateOrigin": "top-left",
        "coordinateSpace": "normalized",
    }


def _validate_normalized(value: Any, field: str) -> float:
    result = _finite_number(value, field)
    if not 0.0 <= result <= 1.0:
        raise ValidationError(f"{field} must be between 0 and 1")
    return result


def _reference_frames(payload: Mapping[str, Any]) -> List[Frame]:
    raw_frames = payload.get("frames")
    if not isinstance(raw_frames, list):
        raise ValidationError("reference.frames must be an array")
    frames: List[Frame] = []
    previous_timestamp: Optional[float] = None
    for index, raw in enumerate(raw_frames):
        if not isinstance(raw, Mapping):
            raise ValidationError(f"reference.frames[{index}] must be an object")
        timestamp = _finite_number(raw.get("timestamp"), f"reference.frames[{index}].timestamp")
        if timestamp < 0:
            raise ValidationError(f"reference.frames[{index}].timestamp must not be negative")
        if previous_timestamp is not None and timestamp <= previous_timestamp:
            raise ValidationError("reference frame timestamps must be strictly increasing source PTS values")
        previous_timestamp = timestamp
        visibility = _required_string(raw.get("visibility"), f"reference.frames[{index}].visibility")
        if visibility not in VISIBILITIES:
            raise ValidationError(f"reference.frames[{index}].visibility is not recognised")
        review_status = _required_string(raw.get("reviewStatus"), f"reference.frames[{index}].reviewStatus")
        if review_status not in REVIEW_STATUSES:
            raise ValidationError(f"reference.frames[{index}].reviewStatus is not recognised")
        x = _optional_finite_number(raw.get("x"), f"reference.frames[{index}].x")
        y = _optional_finite_number(raw.get("y"), f"reference.frames[{index}].y")
        if visibility == "visible":
            if x is None or y is None:
                raise ValidationError(f"reference.frames[{index}] visible labels require x and y")
            x = _validate_normalized(x, f"reference.frames[{index}].x")
            y = _validate_normalized(y, f"reference.frames[{index}].y")
        elif x is not None:
            x = _validate_normalized(x, f"reference.frames[{index}].x")
        if visibility != "visible" and y is not None:
            y = _validate_normalized(y, f"reference.frames[{index}].y")
        uncertainty_px = _optional_finite_number(raw.get("uncertaintyPx"), f"reference.frames[{index}].uncertaintyPx")
        if uncertainty_px is not None and uncertainty_px < 0:
            raise ValidationError(f"reference.frames[{index}].uncertaintyPx must not be negative")
        candidate_eligible = raw.get("candidateEligible", True)
        if not isinstance(candidate_eligible, bool):
            raise ValidationError(f"reference.frames[{index}].candidateEligible must be boolean")
        frames.append(Frame(index, timestamp, x, y, visibility, review_status, uncertainty_px, candidate_eligible))
    return frames


def _prediction_points(raw_points: Any, field: str, *, strict_timestamps: bool) -> List[Point]:
    if not isinstance(raw_points, list):
        raise ValidationError(f"{field} must be an array")
    points: List[Point] = []
    previous_timestamp: Optional[float] = None
    for index, raw in enumerate(raw_points):
        if not isinstance(raw, Mapping):
            raise ValidationError(f"{field}[{index}] must be an object")
        timestamp = _finite_number(raw.get("timestamp"), f"{field}[{index}].timestamp")
        if timestamp < 0:
            raise ValidationError(f"{field}[{index}].timestamp must not be negative")
        if previous_timestamp is not None:
            if strict_timestamps and timestamp <= previous_timestamp:
                raise ValidationError(f"{field} timestamps must be strictly increasing source PTS values")
            if not strict_timestamps and timestamp < previous_timestamp:
                raise ValidationError(f"{field} timestamps must be non-decreasing source PTS values")
        previous_timestamp = timestamp
        x = _validate_normalized(raw.get("x"), f"{field}[{index}].x")
        y = _validate_normalized(raw.get("y"), f"{field}[{index}].y")
        points.append(Point(index, timestamp, x, y))
    return points


def _safe_identifier(value: Any) -> Optional[str]:
    """Keep opaque provenance identifiers while excluding paths and coordinate payloads."""
    if not isinstance(value, str) or not value.strip() or len(value) > 512:
        return None
    if any(character in value for character in ("/", "\\", "\n", "\r")):
        return None
    return value


def _safe_provenance_mapping(value: Any, *, source_hashes: bool = False) -> Optional[Dict[str, Any]]:
    if not isinstance(value, Mapping):
        return None
    result: Dict[str, Any] = {}
    for key, item in value.items():
        if not isinstance(key, str):
            continue
        if source_hashes:
            safe = _safe_identifier(item)
        elif key in _IDENTIFIER_KEYS:
            safe = _safe_identifier(item)
        else:
            safe = None
        if safe is not None:
            result[key] = safe
    return result or None


def _prediction_provenance(payload: Mapping[str, Any]) -> Dict[str, Any]:
    """Return the small allowlist of provenance fields safe for aggregate reports."""
    result: Dict[str, Any] = {}
    for key in _PROVENANCE_SCALAR_KEYS:
        if key in payload:
            safe = _safe_identifier(payload[key])
            if safe is not None:
                result[key] = safe
    if "sourceHashes" in payload:
        safe_hashes = _safe_provenance_mapping(payload["sourceHashes"], source_hashes=True)
        if safe_hashes is not None:
            result["sourceHashes"] = safe_hashes
    for key in ("replay", "adapter", "checkpoint"):
        if key in payload:
            safe_identifiers = _safe_provenance_mapping(payload[key])
            if safe_identifiers is not None:
                result[key] = safe_identifiers
    return result


def validate_reference(payload: Mapping[str, Any]) -> Tuple[Dict[str, Any], List[Frame]]:
    if not isinstance(payload, Mapping):
        raise ValidationError("reference must be a JSON object")
    return _metadata(payload, "reference"), _reference_frames(payload)


def validate_prediction(payload: Mapping[str, Any]) -> Tuple[Dict[str, Any], List[Point], Optional[List[Point]], Dict[str, Any]]:
    if not isinstance(payload, Mapping):
        raise ValidationError("prediction must be a JSON object")
    metadata = _metadata(payload, "prediction")
    mode = _required_string(payload.get("mode"), "prediction.mode")
    if mode not in MODES:
        raise ValidationError("prediction.mode must be 'automatic' or 'assisted'")
    prompt_count = payload.get("promptCount", 0)
    correction_count = payload.get("correctionCount", 0)
    for value, field in ((prompt_count, "prediction.promptCount"), (correction_count, "prediction.correctionCount")):
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise ValidationError(f"{field} must be a non-negative integer")
    points = _prediction_points(payload.get("frames"), "prediction.frames", strict_timestamps=True)
    candidates = None
    if "candidates" in payload:
        # Multiple candidates may share a source PTS, so only non-decreasing order is required.
        candidates = _prediction_points(payload.get("candidates"), "prediction.candidates", strict_timestamps=False)
    return metadata, points, candidates, {
        "mode": mode,
        "promptCount": prompt_count,
        "correctionCount": correction_count,
        **_prediction_provenance(payload),
    }


def _match_points(
    reference: Sequence[Frame], points: Sequence[Point], tolerance_seconds: float
) -> Dict[int, int]:
    """Return one-to-one nearest timestamp matches; no interpolation is performed."""
    return _match_timestamps(reference, [point.timestamp for point in points], tolerance_seconds)


def _match_timestamps(
    reference: Sequence[Frame], point_times: Sequence[float], tolerance_seconds: float
) -> Dict[int, int]:
    """Match the maximum-cardinality monotonic set, then minimise timestamp error.

    Two compact DP rows hold cardinality and cost; a byte per cell records the choice for
    deterministic backtracking. This avoids retaining Python tuples for every state while
    remaining appropriate for short source-timed clips.
    """
    if tolerance_seconds < 0:
        raise ValueError("tolerance_seconds must not be negative")
    ref_count = len(reference)
    point_count = len(point_times)
    if not ref_count or not point_count:
        return {}

    stride = point_count + 1
    choices = bytearray((ref_count + 1) * stride)
    for point_index in range(1, point_count + 1):
        choices[point_index] = 1  # skip point in the empty-reference row

    previous_counts = array("i", [0]) * stride
    previous_costs = array("d", [0.0]) * stride
    for ref_index in range(1, ref_count + 1):
        current_counts = array("i", [0]) * stride
        current_costs = array("d", [0.0]) * stride
        choices[ref_index * stride] = 0  # skip reference in the empty-point column
        frame = reference[ref_index - 1]
        for point_index in range(1, point_count + 1):
            best_count = previous_counts[point_index]
            best_cost = previous_costs[point_index]
            best_choice = 0  # prefer skipping the reference on an exact tie

            left_count = current_counts[point_index - 1]
            left_cost = current_costs[point_index - 1]
            if left_count > best_count or (left_count == best_count and left_cost < best_cost - 1e-15):
                best_count, best_cost, best_choice = left_count, left_cost, 1

            timestamp_error = abs(point_times[point_index - 1] - frame.timestamp)
            if timestamp_error <= tolerance_seconds:
                diagonal_count = previous_counts[point_index - 1] + 1
                diagonal_cost = previous_costs[point_index - 1] + timestamp_error
                if (
                    diagonal_count > best_count
                    or (diagonal_count == best_count and diagonal_cost < best_cost - 1e-15)
                    or (diagonal_count == best_count and abs(diagonal_cost - best_cost) <= 1e-15 and best_choice != 2)
                ):
                    best_count, best_cost, best_choice = diagonal_count, diagonal_cost, 2

            current_counts[point_index] = best_count
            current_costs[point_index] = best_cost
            choices[ref_index * stride + point_index] = best_choice
        previous_counts, current_counts = current_counts, previous_counts
        previous_costs, current_costs = current_costs, previous_costs

    matches: Dict[int, int] = {}
    ref_index, point_index = ref_count, point_count
    while ref_index > 0 and point_index > 0:
        choice = choices[ref_index * stride + point_index]
        if choice == 2:
            matches[ref_index - 1] = point_index - 1
            ref_index -= 1
            point_index -= 1
        elif choice == 1:
            point_index -= 1
        else:
            ref_index -= 1
    return dict(sorted(matches.items()))


def _group_points_by_timestamp(points: Sequence[Point]) -> List[PointGroup]:
    groups: List[PointGroup] = []
    for point in points:
        if groups and point.timestamp == groups[-1].timestamp:
            previous = groups[-1]
            groups[-1] = PointGroup(previous.index, previous.timestamp, previous.points + (point,))
        else:
            groups.append(PointGroup(len(groups), point.timestamp, (point,)))
    return groups


def _pixel_error(frame: Frame, point: Point, width: int, height: int) -> float:
    assert frame.x is not None and frame.y is not None
    return math.hypot((point.x - frame.x) * width, (point.y - frame.y) * height)


def _ratio(numerator: int, denominator: int) -> Optional[float]:
    return numerator / denominator if denominator else None


def _percentile(values: Iterable[float], percentile: float) -> Optional[float]:
    ordered = sorted(values)
    if not ordered:
        return None
    if len(ordered) == 1:
        return ordered[0]
    rank = (len(ordered) - 1) * percentile
    lower = math.floor(rank)
    upper = math.ceil(rank)
    if lower == upper:
        return ordered[lower]
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (rank - lower)


def _error_summary(errors: Sequence[float]) -> Dict[str, Optional[float]]:
    return {
        "matchedFrames": len(errors),
        "medianPx": _percentile(errors, 0.50),
        "p95Px": _percentile(errors, 0.95),
        "maxPx": max(errors) if errors else None,
    }


def _coverage_entry(frames: Sequence[Frame], matches: Mapping[int, int], status: Optional[str] = None) -> Dict[str, Any]:
    visible = [frame for frame in frames if frame.visibility == "visible" and (status is None or frame.review_status == status)]
    matched = sum(frame.index in matches for frame in visible)
    return {
        "visibleFrames": len(visible),
        "matchedVisibleFrames": matched,
        "coverage": _ratio(matched, len(visible)),
    }


def _longest_visible_interval(frames: Sequence[Frame], included_indices: set) -> Optional[Dict[str, Any]]:
    """Return the longest run, with every non-visible label acting as a boundary."""
    runs: List[List[Frame]] = []
    current: List[Frame] = []
    for frame in frames:
        if frame.visibility == "visible" and frame.index in included_indices:
            current.append(frame)
        else:
            if current:
                runs.append(current)
            current = []
    if current:
        runs.append(current)
    if not runs:
        return None
    longest = max(runs, key=lambda run: (run[-1].timestamp - run[0].timestamp, len(run)))
    start = longest[0].timestamp
    end = longest[-1].timestamp
    return {
        "startTimestamp": start,
        "endTimestamp": end,
        "durationSeconds": end - start,
        "frameCount": len(longest),
    }


def _missing_interval(frames: Sequence[Frame], matches: Mapping[int, int]) -> Optional[Dict[str, Any]]:
    missing_indices = {
        frame.index for frame in frames if frame.visibility == "visible" and frame.index not in matches
    }
    return _longest_visible_interval(frames, missing_indices)


def score(
    reference_payload: Mapping[str, Any],
    prediction_payload: Mapping[str, Any],
    *,
    tolerance_ms: float = 20.0,
    hit_tolerance_px: float = 12.0,
) -> Dict[str, Any]:
    """Score validated JSON-like payloads and return aggregate metrics only."""
    if not math.isfinite(tolerance_ms) or tolerance_ms < 0:
        raise ValidationError("tolerance_ms must be a finite non-negative number")
    if not math.isfinite(hit_tolerance_px) or hit_tolerance_px < 0:
        raise ValidationError("hit_tolerance_px must be a finite non-negative number")
    reference_meta, reference_frames = validate_reference(reference_payload)
    prediction_meta, prediction_points, candidates, prediction_meta_extra = validate_prediction(prediction_payload)
    for field in ("clipId", "sourceHash", "width", "height", "coordinateOrigin", "coordinateSpace"):
        if reference_meta[field] != prediction_meta[field]:
            raise ValidationError(f"reference and prediction {field} do not match")
    tolerance_seconds = tolerance_ms / 1000.0

    matchable_frames = [frame for frame in reference_frames if frame.visibility != "uncertain"]
    matches = _match_points(matchable_frames, prediction_points, tolerance_seconds)
    # _match_points receives a compact list; translate back to original frame indices.
    translated_matches = {matchable_frames[compact_index].index: point_index for compact_index, point_index in matches.items()}

    visible_frames = [frame for frame in reference_frames if frame.visibility == "visible"]
    visible_errors = [
        _pixel_error(frame, prediction_points[translated_matches[frame.index]], reference_meta["width"], reference_meta["height"])
        for frame in visible_frames
        if frame.index in translated_matches
    ]
    absolute_hit_indices = set()
    uncertainty_aware_hit_indices = set()
    uncertainty_aware_hits = 0
    error_cursor = 0
    for frame in visible_frames:
        if frame.index not in translated_matches:
            continue
        error = visible_errors[error_cursor]
        error_cursor += 1
        if error <= hit_tolerance_px:
            absolute_hit_indices.add(frame.index)
        effective_tolerance = max(hit_tolerance_px, frame.uncertainty_px or 0.0)
        if error <= effective_tolerance:
            uncertainty_aware_hit_indices.add(frame.index)
    absolute_hits = len(absolute_hit_indices)
    uncertainty_aware_hits = len(uncertainty_aware_hit_indices)
    matched_visible_indices = {frame.index for frame in visible_frames if frame.index in translated_matches}
    wrong_absolute_indices = matched_visible_indices - absolute_hit_indices
    wrong_uncertainty_aware_indices = matched_visible_indices - uncertainty_aware_hit_indices

    provenance = {
        status: _coverage_entry(reference_frames, translated_matches, status)
        for status in sorted(REVIEW_STATUSES)
    }
    reviewed_visible = [frame for frame in visible_frames if frame.review_status in REVIEWED_STATUSES]
    human_verified_visible = [frame for frame in visible_frames if frame.review_status == "human-verified"]
    absent_frames = [frame for frame in reference_frames if frame.visibility in ABSENT_VISIBILITIES]
    false_by_state = {
        state: sum(frame.index in translated_matches for frame in absent_frames if frame.visibility == state)
        for state in sorted(ABSENT_VISIBILITIES)
    }
    false_predictions = sum(false_by_state.values())

    candidate_result: Dict[str, Any]
    if candidates is None:
        candidate_result = {"available": False}
    else:
        candidate_frames = [frame for frame in visible_frames if frame.candidate_eligible]
        candidate_groups = _group_points_by_timestamp(candidates)
        candidate_matches = _match_timestamps(
            candidate_frames, [group.timestamp for group in candidate_groups], tolerance_seconds
        )
        candidate_hits = 0
        for compact_index, candidate_group_index in candidate_matches.items():
            frame = candidate_frames[compact_index]
            group = candidate_groups[candidate_group_index]
            minimum_error = min(
                _pixel_error(frame, point, reference_meta["width"], reference_meta["height"])
                for point in group.points
            )
            if minimum_error <= hit_tolerance_px:
                candidate_hits += 1
        candidate_result = {
            "available": True,
            "eligibleVisibleFrames": len(candidate_frames),
            "matchedCandidateFrames": len(candidate_matches),
            "candidateHits": candidate_hits,
            "recall": _ratio(candidate_hits, len(candidate_frames)),
        }

    report = {
        "schemaVersion": SCHEMA_VERSION,
        "source": {
            "clipId": reference_meta["clipId"],
            "sourceHash": reference_meta["sourceHash"],
            "width": reference_meta["width"],
            "height": reference_meta["height"],
            "coordinateOrigin": reference_meta["coordinateOrigin"],
            "coordinateSpace": reference_meta["coordinateSpace"],
        },
        "matching": {
            "timestampToleranceMs": tolerance_ms,
            "matchedReferenceFrames": len(translated_matches),
            "unmatchedPredictionFrames": len(prediction_points) - len(set(translated_matches.values())),
            "interpolation": False,
        },
        "prediction": prediction_meta_extra,
        "referenceProvenance": {
            "statusCounts": {
                status: sum(frame.review_status == status for frame in reference_frames)
                for status in sorted(REVIEW_STATUSES)
            },
            "coverageByStatus": provenance,
            "reviewedStatuses": sorted(REVIEWED_STATUSES),
        },
        "visible": {
            "visibleFrames": len(visible_frames),
            "matchedVisibleFrames": len(visible_errors),
            "localisationHitsWithinTolerance": {
                "absolutePixelTolerance": {
                    "tolerancePx": hit_tolerance_px,
                    "hits": absolute_hits,
                    "rateAmongMatchedVisible": _ratio(absolute_hits, len(visible_errors)),
                    "coverageAllVisible": _ratio(absolute_hits, len(visible_frames)),
                    "coverageReviewedVisible": _ratio(
                        sum(frame.index in absolute_hit_indices for frame in reviewed_visible), len(reviewed_visible)
                    ),
                    "coverageHumanVerifiedVisible": _ratio(
                        sum(frame.index in absolute_hit_indices for frame in human_verified_visible), len(human_verified_visible)
                    ),
                },
                "uncertaintyAware": {
                    "hits": uncertainty_aware_hits,
                    "acceptedOnlyByUncertainty": uncertainty_aware_hits - absolute_hits,
                    "rateAmongMatchedVisible": _ratio(uncertainty_aware_hits, len(visible_errors)),
                    "coverageAllVisible": _ratio(uncertainty_aware_hits, len(visible_frames)),
                    "coverageReviewedVisible": _ratio(
                        sum(frame.index in uncertainty_aware_hit_indices for frame in reviewed_visible), len(reviewed_visible)
                    ),
                    "coverageHumanVerifiedVisible": _ratio(
                        sum(frame.index in uncertainty_aware_hit_indices for frame in human_verified_visible), len(human_verified_visible)
                    ),
                },
            },
            "onTimeButWrong": {
                "absolutePixelTolerance": {
                    "count": len(visible_errors) - absolute_hits,
                    "rateAmongMatchedVisible": _ratio(len(visible_errors) - absolute_hits, len(visible_errors)),
                },
                "uncertaintyAware": {
                    "count": len(visible_errors) - uncertainty_aware_hits,
                    "rateAmongMatchedVisible": _ratio(len(visible_errors) - uncertainty_aware_hits, len(visible_errors)),
                },
            },
            "errorsPx": _error_summary(visible_errors),
            "coverage": {
                "overallVisible": _ratio(len(visible_errors), len(visible_frames)),
                "reviewedSubset": _ratio(
                    sum(frame.index in translated_matches for frame in reviewed_visible), len(reviewed_visible)
                ),
                "humanVerifiedSubset": _ratio(
                    sum(frame.index in translated_matches for frame in human_verified_visible), len(human_verified_visible)
                ),
            },
            "missingVisibleFrames": len(visible_frames) - len(visible_errors),
            "longestMissingInterval": _missing_interval(reference_frames, translated_matches),
            "longestWrongLocalisationInterval": {
                "absolutePixelTolerance": _longest_visible_interval(reference_frames, wrong_absolute_indices),
                "uncertaintyAware": _longest_visible_interval(reference_frames, wrong_uncertainty_aware_indices),
            },
        },
        "explicitAbsent": {
            "states": sorted(ABSENT_VISIBILITIES),
            "labelFrames": len(absent_frames),
            "falsePredictions": false_predictions,
            "falsePredictionRate": _ratio(false_predictions, len(absent_frames)),
            "falsePredictionsByState": false_by_state,
            "uncertainFramesExcluded": sum(frame.visibility == "uncertain" for frame in reference_frames),
        },
        "candidateRecall": candidate_result,
        "identity": {"assessed": False, "reason": "Identity errors are not inferred from path smoothness."},
    }
    return report


def _load_json(path: Path, kind: str) -> Mapping[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as stream:
            value = json.load(stream)
    except (OSError, json.JSONDecodeError) as error:
        raise ValidationError(f"could not read {kind} JSON") from error
    if not isinstance(value, Mapping):
        raise ValidationError(f"{kind} JSON must contain an object")
    return value


def _repo_root() -> Optional[Path]:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=Path(__file__).resolve().parent,
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None
    return Path(result.stdout.strip()).resolve()


def _is_within(path: Path, directory: Path) -> bool:
    try:
        path.relative_to(directory)
        return True
    except ValueError:
        return False


def _enforce_private_path(path: Path, *, allow_synthetic_example: bool, repo_root: Optional[Path]) -> None:
    if repo_root is None or not _is_within(path, repo_root):
        return
    examples = repo_root / "Tools" / "TracerHarness" / "examples"
    if allow_synthetic_example and _is_within(path, examples):
        return
    raise ValidationError("real references, predictions and reports must be outside the repository; use only synthetic examples in Git")


def _text_report(report: Mapping[str, Any]) -> str:
    visible = report["visible"]
    matching = report["matching"]
    absent = report["explicitAbsent"]
    errors = visible["errorsPx"]
    prediction = report["prediction"]
    lines = [
        f"clip {report['source']['clipId']} · mode={prediction['mode']} prompts={prediction['promptCount']} corrections={prediction['correctionCount']}",
        f"matched visible frames: {visible['matchedVisibleFrames']}/{visible['visibleFrames']} · coverage overall={visible['coverage']['overallVisible']} reviewed={visible['coverage']['reviewedSubset']}",
        f"localisation hits <= {visible['localisationHitsWithinTolerance']['absolutePixelTolerance']['tolerancePx']}px: {visible['localisationHitsWithinTolerance']['absolutePixelTolerance']['hits']} · uncertainty-aware: {visible['localisationHitsWithinTolerance']['uncertaintyAware']['hits']}",
        f"errors px: median={errors['medianPx']} p95={errors['p95Px']} max={errors['maxPx']}",
        f"missing visible frames: {visible['missingVisibleFrames']} · longest source interval={visible['longestMissingInterval']}",
        f"on-time-but-wrong gaps: absolute={visible['longestWrongLocalisationInterval']['absolutePixelTolerance']} uncertainty-aware={visible['longestWrongLocalisationInterval']['uncertaintyAware']}",
        f"false predictions on explicit absent states: {absent['falsePredictions']}/{absent['labelFrames']} (uncertain excluded)",
        f"timestamp tolerance: {matching['timestampToleranceMs']}ms · interpolation={matching['interpolation']}",
    ]
    candidate = report["candidateRecall"]
    if candidate["available"]:
        lines.append(f"candidate recall: {candidate['candidateHits']}/{candidate['eligibleVisibleFrames']} = {candidate['recall']}")
    else:
        lines.append("candidate recall: unavailable")
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Score source-timed tracer predictions against explicit reference labels.")
    parser.add_argument("--reference", required=True, type=Path, help="reference JSON (private path or synthetic example)")
    parser.add_argument("--prediction", required=True, type=Path, help="prediction JSON (private path or synthetic example)")
    parser.add_argument("--tolerance-ms", type=float, default=20.0, help="maximum timestamp difference for one-to-one matching")
    parser.add_argument("--hit-tolerance-px", type=float, default=12.0, help="absolute pixel distance for a localisation hit")
    parser.add_argument("--format", choices=("text", "json"), default="text", help="aggregate report format")
    parser.add_argument("--report", type=Path, help="write aggregate JSON report outside the repository")
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    repo_root = _repo_root()
    try:
        reference_path = args.reference.resolve()
        prediction_path = args.prediction.resolve()
        _enforce_private_path(reference_path, allow_synthetic_example=True, repo_root=repo_root)
        _enforce_private_path(prediction_path, allow_synthetic_example=True, repo_root=repo_root)
        if args.report:
            _enforce_private_path(args.report.resolve(), allow_synthetic_example=False, repo_root=repo_root)
        reference = _load_json(reference_path, "reference")
        prediction = _load_json(prediction_path, "prediction")
        report = score(reference, prediction, tolerance_ms=args.tolerance_ms, hit_tolerance_px=args.hit_tolerance_px)
        rendered = json.dumps(report, indent=2, sort_keys=True) if args.format == "json" else _text_report(report)
        if args.report:
            args.report.resolve().write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        print(rendered)
        return 0
    except (ValidationError, OSError) as error:
        print(f"benchmark error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
