#!/usr/bin/env python3
"""Replay existing candidate pools through one supplied ball point.

This standard-library research adapter never invokes a detector or reads label
files. A private configuration supplies source metadata, one point, the existing
NDJSON candidate pool and its manifest. Every output is an unchanged raw
candidate. The seed and constant-velocity predictions constrain association
only; neither interpolated points nor missing-frame positions are emitted.

Example:
  python3 Tools/TracerHarness/alternatives/seeded_candidate_replay.py \
    --config /private/review/replay-config.json \
    --output /private/review/replay-prediction.json
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import math
from pathlib import Path
import time


# Frozen shared research defaults; no per-clip parameter overrides are accepted.
PARAMETERS = {
    "beam_width": 64,
    "maximum_gap_seconds": 0.20,
    "maximum_speed_diagonals_per_second": 1.5,
    "maximum_acceleration_diagonals_per_second_squared": 3.0,
    "position_noise_diagonals": 0.002,
    "seed_radius_diagonals": 0.0025,
    "match_reward": 1.0,
    "confidence_weight": 0.35,
    "residual_penalty_weight": 0.8,
    "miss_penalty": 0.2,
}


@dataclass(frozen=True)
class Candidate:
    identifier: int
    row: int
    time: float
    x: float
    y: float
    confidence: float


@dataclass(frozen=True)
class State:
    score: float
    time: float
    x: float
    y: float
    velocity_x: float | None
    velocity_y: float | None
    history: tuple[int, ...]


def outside(path: str | Path, kind: str) -> Path:
    resolved = Path(path).expanduser().resolve()
    if resolved.is_relative_to(Path(__file__).resolve().parents[3]):
        raise ValueError(f"{kind} must remain outside the repository")
    return resolved


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def finite_number(value: object, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"{name} must be a finite number")
    return float(value)


def validate_source_contract(manifest: dict, info: dict) -> dict:
    expected = "normalised top-left origin; sourceTime is absolute source presentation time in seconds"
    if manifest.get("coordinateSystem") != expected:
        raise ValueError("Candidate manifest coordinate or source-time contract is unsupported")
    video = manifest.get("sourceVideo", {})
    native_width, native_height = video.get("nativeWidth"), video.get("nativeHeight")
    if (type(native_width) is not int or type(native_height) is not int
            or min(native_width, native_height) <= 0):
        raise ValueError("Candidate manifest native dimensions must be positive integers")
    transform = video.get("preferredTransform")
    if not isinstance(transform, list) or len(transform) != 6:
        raise ValueError("Candidate manifest must contain a six-element preferred transform")
    a,b,c,d,tx,ty = [finite_number(v, "Preferred transform") for v in transform]
    if abs(a*d-b*c) < 1e-12:
        raise ValueError("Candidate manifest preferred transform is singular")
    corners = [(a*x+c*y+tx, b*x+d*y+ty)
               for x,y in ((0,0),(native_width,0),(0,native_height),(native_width,native_height))]
    extent_width = max(p[0] for p in corners)-min(p[0] for p in corners)
    extent_height = max(p[1] for p in corners)-min(p[1] for p in corners)
    upright_width, upright_height = round(extent_width), round(extent_height)
    if (min(upright_width, upright_height) <= 0
            or abs(extent_width-upright_width) > 1e-6
            or abs(extent_height-upright_height) > 1e-6):
        raise ValueError("Candidate manifest has ambiguous upright pixel dimensions")
    explicit = "uprightWidth" in video or "uprightHeight" in video
    if explicit and (video.get("uprightWidth"),video.get("uprightHeight")) != (upright_width,upright_height):
        raise ValueError("Candidate manifest upright dimensions disagree with its preferred transform")
    if (info["width"],info["height"]) != (upright_width,upright_height):
        raise ValueError("Configuration dimensions disagree with the candidate manifest upright dimensions")
    impact = finite_number(manifest.get("controlledImpactTime"), "Supplied impact time")
    if impact < 0:
        raise ValueError("Supplied impact time must be non-negative")
    return {"coordinateContract":expected,"uprightWidth":upright_width,
            "uprightHeight":upright_height,
            "dimensionEvidence":"explicit manifest plus preferred transform" if explicit
            else "legacy manifest native dimensions plus preferred transform",
            "controlledImpactTime":impact}


def replay_direction(rows: list[tuple[float, list[Candidate]]], seed: dict,
                     width: int, height: int, diagonal: float) -> tuple[State, int]:
    """Beam association outward from the seed; rows determine time direction."""
    active = [State(0.0, seed["timestamp"], seed["x"]*width,
                    seed["y"]*height, None, None, ())]
    best = active[0]
    examined = 0
    maximum_speed = PARAMETERS["maximum_speed_diagonals_per_second"]*diagonal
    maximum_acceleration = PARAMETERS["maximum_acceleration_diagonals_per_second_squared"]*diagonal
    position_noise = PARAMETERS["position_noise_diagonals"]*diagonal
    for timestamp, candidates in rows:
        successors = []
        for state in active:
            signed_dt = timestamp-state.time
            dt = abs(signed_dt)
            if dt <= 0 or dt > PARAMETERS["maximum_gap_seconds"]+1e-9:
                continue
            # Skipping retains the last real observation and its true source PTS.
            successors.append(State(state.score-PARAMETERS["miss_penalty"],
                                    state.time, state.x, state.y,
                                    state.velocity_x, state.velocity_y, state.history))
            for candidate in candidates:
                examined += 1
                x, y = candidate.x*width, candidate.y*height
                speed = math.hypot(x-state.x, y-state.y)/dt
                if speed > maximum_speed:
                    continue
                if state.velocity_x is None:
                    residual_fraction = speed/maximum_speed
                else:
                    predicted_x = state.x+state.velocity_x*signed_dt
                    predicted_y = state.y+state.velocity_y*signed_dt
                    residual = math.hypot(x-predicted_x, y-predicted_y)
                    tolerance = position_noise+0.5*maximum_acceleration*dt*dt
                    if residual > tolerance:
                        continue
                    residual_fraction = residual/tolerance
                reward = (PARAMETERS["match_reward"]
                          + PARAMETERS["confidence_weight"]*candidate.confidence
                          - PARAMETERS["residual_penalty_weight"]*residual_fraction**2)
                successors.append(State(
                    state.score+reward, timestamp, x, y,
                    (x-state.x)/signed_dt, (y-state.y)/signed_dt,
                    state.history+(candidate.identifier,)))
        if not successors:
            break
        # Paths with identical last observations have identical future motion;
        # retain only the highest scoring history for each such state.
        unique = {}
        for state in sorted(successors, key=lambda s: (s.score, len(s.history)), reverse=True):
            key = state.history[-2:]
            if key not in unique:
                unique[key] = state
        active = list(unique.values())[:PARAMETERS["beam_width"]]
        if (active[0].score, len(active[0].history)) > (best.score, len(best.history)):
            best = active[0]
    return best, examined


def run() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    started = time.perf_counter()
    config_path = outside(args.config, "Private configuration")
    output_path = outside(args.output, "Private predictions")
    config = json.loads(config_path.read_text())
    if "parameters" in config:
        raise ValueError("Per-clip parameter overrides are not supported")
    pool_path = outside(config["candidate_events"], "Candidate pool")
    manifest_path = outside(config["pool_manifest"], "Candidate manifest")
    manifest = json.loads(manifest_path.read_text())
    info = config["source_metadata"]
    required = ("clipId", "sourceHash", "width", "height", "coordinateOrigin", "coordinateSpace")
    if any(key not in info for key in required):
        raise ValueError("Missing source metadata")
    if info["coordinateOrigin"] != "top-left" or info["coordinateSpace"] != "normalized":
        raise ValueError("Only top-left normalised source coordinates are supported")
    width, height = info["width"], info["height"]
    if not isinstance(width, int) or not isinstance(height, int) or min(width, height) <= 0:
        raise ValueError("Source dimensions must be positive integers")
    diagonal = math.hypot(width, height)
    if info["sourceHash"] != "sha256:"+manifest["sourceSHA256"]:
        raise ValueError("Candidate pool source hash disagrees with configuration")
    source_contract = validate_source_contract(manifest, info)
    seed = config["seed"]
    seed = {key:finite_number(seed[key], "Seed field") for key in ("timestamp", "x", "y")}
    if seed["timestamp"] < 0 or not 0 <= seed["x"] <= 1 or not 0 <= seed["y"] <= 1:
        raise ValueError("Seed is outside source time or image bounds")
    rows, all_candidates = [], []
    for row_index, line in enumerate(pool_path.read_text().splitlines()):
        record = json.loads(line)
        timestamp = finite_number(record["sourceTime"], "Candidate row time")
        if timestamp < 0 or (rows and timestamp <= rows[-1][0]):
            raise ValueError("Candidate rows must have strictly increasing source PTS")
        candidates = []
        for raw in record["candidates"]:
            candidate_time = finite_number(raw["sourceTime"], "Candidate time")
            if abs(candidate_time-timestamp) > 1e-9:
                raise ValueError("Candidate and row source PTS differ")
            x = finite_number(raw["normalizedX"], "Candidate coordinate")
            y = finite_number(raw["normalizedY"], "Candidate coordinate")
            confidence = finite_number(raw["confidence"], "Candidate confidence")
            if not 0 <= x <= 1 or not 0 <= y <= 1 or not 0 <= confidence <= 1:
                raise ValueError("Candidate coordinates or confidence are outside normalised bounds")
            candidate = Candidate(len(all_candidates), row_index, timestamp, x, y, confidence)
            candidates.append(candidate)
            all_candidates.append(candidate)
        rows.append((timestamp, candidates))
    if not rows or not rows[0][0] <= seed["timestamp"] <= rows[-1][0]:
        raise ValueError("Seed must be inside the candidate-pool interval")
    before = [(t, cs) for t, cs in reversed(rows) if t < seed["timestamp"]-1e-9]
    after = [(t, cs) for t, cs in rows if t > seed["timestamp"]+1e-9]
    seed_candidates = [c for t, cs in rows if abs(t-seed["timestamp"]) <= 1e-9 for c in cs]
    seed_candidates = [c for c in seed_candidates
                       if math.hypot((c.x-seed["x"])*width, (c.y-seed["y"])*height)
                       <= PARAMETERS["seed_radius_diagonals"]*diagonal]
    seed_match = min(seed_candidates,
                     key=lambda c: math.hypot((c.x-seed["x"])*width, (c.y-seed["y"])*height),
                     default=None)
    backward, backward_examined = replay_direction(before, seed, width, height, diagonal)
    forward, forward_examined = replay_direction(after, seed, width, height, diagonal)
    identifiers = list(backward.history)+list(forward.history)
    if seed_match is not None:
        identifiers.append(seed_match.identifier)
    selected = sorted((all_candidates[i] for i in identifiers), key=lambda c:c.time)
    if any(b.time <= a.time for a,b in zip(selected, selected[1:])):
        raise RuntimeError("Replay produced duplicate source timestamps")
    result = {
        "schemaVersion":"1.0", **{key:info[key] for key in required},
        "mode":"assisted", "promptCount":2, "pointPromptCount":1,
        "timingPromptCount":1, "correctionCount":0,
        "frames":[{"timestamp":c.time,"x":c.x,"y":c.y,"confidence":c.confidence}
                  for c in selected],
        "candidates":[{"timestamp":c.time,"x":c.x,"y":c.y,"confidence":c.confidence}
                      for c in all_candidates],
        "assistance":{
            "pointPromptCount":1,"timingPromptCount":1,
            "pointSeed":seed,"seedSource":config.get("seed_source","supplied source ball point"),
            "seedUsedOnlyAsConstraint":True,"seedCoordinateEmitted":False,
            "actualCandidateAtSeedFrameEmitted":seed_match is not None,
            "controlledImpactTime":source_contract["controlledImpactTime"],
            "candidatePoolVariant":manifest.get("variant"),
            "candidatePoolSearchDependence":"Existing baseline search regions and cadence; later ROI availability depends on baseline association. This replay cannot establish new acquisition or full-frame candidate recall.",
            "usesFutureEvidence":True,"automaticAcquisitionDemonstrated":False,
            "relabelledOrRetimedCandidates":False,"interpolatedOutputPoints":0,
        },
        "replay":{
            "algorithm":"single-seed independent forward/backward constant-velocity beam association",
            "parameters":PARAMETERS,"codeSHA256":digest(Path(__file__)),
            "candidatePoolSHA256":digest(pool_path),"poolManifestSHA256":digest(manifest_path),
            "configurationSHA256":digest(config_path),"poolRows":len(rows),
            "sourceContractValidation":source_contract,
            "rawCandidates":len(all_candidates),"backwardSelected":len(backward.history),
            "forwardSelected":len(forward.history),
            "examinedTransitions":backward_examined+forward_examined,
            "elapsedSeconds":time.perf_counter()-started,
        },
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(result, indent=2)+"\n")
    print(json.dumps({"clipId":info["clipId"],"poolRows":len(rows),
                      "selectedRawCandidates":len(selected),
                      "candidateAtSeedFrame":seed_match is not None,
                      "elapsedSeconds":result["replay"]["elapsedSeconds"]}))


if __name__ == "__main__":
    run()
