#!/usr/bin/env python3
"""Track one supplied first-visible point through private native PNG frames.

This is a research comparator. It uses one declared source-coordinate seed and
full-frame AVFoundation PNGs, then emits only locally observed bright-object
locations at their original source presentation timestamps. It neither reads
labels nor candidate pools and never writes a predicted position after a miss.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
import math
from pathlib import Path
import time
from typing import Any

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageStat
except ImportError as error:  # Keep any dependency installation outside the repository.
    raise SystemExit("Pillow is required; use the isolated external model virtual environment.") from error


# Frozen once for both clips. The private configuration deliberately rejects
# parameter overrides so an outcome cannot tune to a clip's reviewed labels.
PARAMETERS = {
    "camera_proxy_width_px": 192,
    "camera_search_radius_proxy_px": 6,
    "camera_translation_max_source_px": 120,
    "roi_radius_px": 320,
    "maximum_roi_radius_px": 520,
    "maximum_misses": 3,
    "gaussian_radius_px": 4,
    "minimum_highpass": 12,
    "minimum_temporal_difference": 8,
    "minimum_combined_response": 30,
    "minimum_confidence": 0.12,
    "candidate_suppression_radius_px": 16,
    "maximum_candidates_per_frame": 3,
    "seed_timestamp_tolerance_seconds": 0.000_001,
}


REPOSITORY = Path(__file__).resolve().parents[3]


@dataclass(frozen=True)
class SourceFrame:
    index: int
    timestamp: float
    file: Path


@dataclass(frozen=True)
class Observation:
    timestamp: float
    x: float
    y: float
    confidence: float


def outside(value: str | Path, kind: str) -> Path:
    path = Path(value).expanduser().resolve()
    if path == REPOSITORY or REPOSITORY in path.parents:
        raise ValueError(f"{kind} must be outside the repository")
    return path


def finite(value: Any, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise ValueError(f"{name} must be finite")
    return float(value)


def source_metadata(config: dict[str, Any]) -> dict[str, Any]:
    metadata = config.get("source_metadata", config.get("sourceMetadata", config))
    if not isinstance(metadata, dict):
        raise ValueError("Configuration requires source_metadata")
    keys = ("clipId", "sourceHash", "width", "height", "coordinateOrigin", "coordinateSpace")
    if any(key not in metadata for key in keys):
        raise ValueError("source_metadata is incomplete")
    if metadata["coordinateOrigin"] != "top-left" or metadata["coordinateSpace"] != "normalized":
        raise ValueError("Only normalised, top-left source coordinates are supported")
    if not isinstance(metadata["width"], int) or not isinstance(metadata["height"], int):
        raise ValueError("Source dimensions must be integers")
    if metadata["width"] <= 0 or metadata["height"] <= 0:
        raise ValueError("Source dimensions must be positive")
    if not isinstance(metadata["clipId"], str) or not metadata["clipId"]:
        raise ValueError("clipId must be a non-empty string")
    if not isinstance(metadata["sourceHash"], str) or not metadata["sourceHash"].startswith("sha256:"):
        raise ValueError("sourceHash must have a sha256: prefix")
    return {key: metadata[key] for key in keys}


def manifest_path(config: dict[str, Any]) -> Path:
    value = config.get("frame_manifest", config.get("frameManifest"))
    if not isinstance(value, str):
        raise ValueError("Configuration requires frame_manifest")
    return outside(value, "Frame manifest")


def load_frames(path: Path, metadata: dict[str, Any]) -> list[SourceFrame]:
    manifest = json.loads(path.read_text())
    if manifest.get("coordinateOrigin") not in (None, "top-left"):
        raise ValueError("Frame cache origin must be top-left")
    if manifest.get("width") != metadata["width"] or manifest.get("height") != metadata["height"]:
        raise ValueError("Frame cache dimensions do not match source metadata")
    raw_frames = manifest.get("frames")
    if not isinstance(raw_frames, list) or not raw_frames:
        raise ValueError("Frame cache manifest requires frames")
    result: list[SourceFrame] = []
    previous = -math.inf
    for index, item in enumerate(raw_frames):
        if not isinstance(item, dict):
            raise ValueError("Frame cache entries must be objects")
        timestamp = finite(item.get("timestamp"), "Frame timestamp")
        filename = item.get("file")
        if timestamp <= previous or not isinstance(filename, str) or not filename:
            raise ValueError("Frame cache timestamps must strictly increase and include files")
        if item.get("cropX", 0) != 0 or item.get("cropY", 0) != 0:
            raise ValueError("Native point tracking requires uncropped full source frames")
        if "cropWidth" in item and item["cropWidth"] != metadata["width"]:
            raise ValueError("Frame cache crop width is not the source width")
        if "cropHeight" in item and item["cropHeight"] != metadata["height"]:
            raise ValueError("Frame cache crop height is not the source height")
        image_path = outside(path.parent / filename, "Cached source frame")
        if not image_path.is_file():
            raise ValueError("Cached source frame is unavailable")
        result.append(SourceFrame(index=index, timestamp=timestamp, file=image_path))
        previous = timestamp
    return result


def pixel_seed(config: dict[str, Any], width: int, height: int) -> tuple[float, float, float]:
    raw = config.get("seed")
    if not isinstance(raw, dict):
        raise ValueError("Configuration requires one seed")
    timestamp = finite(raw.get("timestamp", raw.get("sourceTime")), "Seed timestamp")
    x = finite(raw.get("x", raw.get("normalizedX")), "Seed x")
    y = finite(raw.get("y", raw.get("normalizedY")), "Seed y")
    if timestamp < 0 or not 0 <= x <= 1 or not 0 <= y <= 1:
        raise ValueError("Seed must be in source-time and normalised-image bounds")
    return timestamp, x * width, y * height


def luminance(path: Path, expected_size: tuple[int, int]) -> Image.Image:
    with Image.open(path) as source:
        image = source.convert("L")
    if image.size != expected_size:
        raise ValueError("Cached source frame dimensions are inconsistent")
    return image


def translation(previous: Image.Image, current: Image.Image, width: int, height: int) -> tuple[float, float]:
    """Estimate global camera movement with a low-resolution absolute-difference search."""
    proxy_width = PARAMETERS["camera_proxy_width_px"]
    proxy_height = max(1, round(height * proxy_width / width))
    previous_proxy = previous.resize((proxy_width, proxy_height), Image.Resampling.BILINEAR)
    current_proxy = current.resize((proxy_width, proxy_height), Image.Resampling.BILINEAR)
    limit = PARAMETERS["camera_search_radius_proxy_px"]
    best: tuple[float, int, int] | None = None
    for dy in range(-limit, limit + 1):
        for dx in range(-limit, limit + 1):
            left, top = max(dx, 0), max(dy, 0)
            right, bottom = min(proxy_width, proxy_width + dx), min(proxy_height, proxy_height + dy)
            if right - left < proxy_width // 2 or bottom - top < proxy_height // 2:
                continue
            current_crop = current_proxy.crop((left, top, right, bottom))
            previous_crop = previous_proxy.crop((left - dx, top - dy, right - dx, bottom - dy))
            score = ImageStat.Stat(ImageChops.difference(current_crop, previous_crop)).mean[0]
            candidate = (score, dx, dy)
            if best is None or candidate < best:
                best = candidate
    assert best is not None
    scale_x, scale_y = width / proxy_width, height / proxy_height
    dx, dy = best[1] * scale_x, best[2] * scale_y
    limit_source = PARAMETERS["camera_translation_max_source_px"]
    if math.hypot(dx, dy) > limit_source:
        return 0.0, 0.0
    return dx, dy


def crop_bounds(x: float, y: float, radius: float, width: int, height: int) -> tuple[int, int, int, int]:
    left = max(0, int(round(x - radius)))
    top = max(0, int(round(y - radius)))
    right = min(width, int(round(x + radius)))
    bottom = min(height, int(round(y + radius)))
    if right <= left or bottom <= top:
        raise ValueError("Predicted ROI is empty")
    return left, top, right, bottom


def maximum_pixel(image: Image.Image) -> tuple[int, int, int] | None:
    """Return the first raster-order pixel at the maximum, never a bbox midpoint."""
    _, peak = image.getextrema()
    if peak <= 0:
        return None
    values = image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()
    for offset, value in enumerate(values):
        if value == peak:
            return offset % image.width, offset // image.width, peak
    return None


def translated_previous_roi(
    previous: Image.Image, bounds: tuple[int, int, int, int], camera_dx: float, camera_dy: float
) -> tuple[Image.Image, Image.Image]:
    """Return an equal-sized previous ROI plus a mask for its valid source overlap."""
    left, top, right, bottom = bounds
    desired_left = left - int(round(camera_dx))
    desired_top = top - int(round(camera_dy))
    desired_right = desired_left + (right - left)
    desired_bottom = desired_top + (bottom - top)
    output = Image.new("L", (right - left, bottom - top))
    valid = Image.new("L", output.size)
    source_left, source_top = max(0, desired_left), max(0, desired_top)
    source_right, source_bottom = min(previous.width, desired_right), min(previous.height, desired_bottom)
    if source_right > source_left and source_bottom > source_top:
        destination = (source_left - desired_left, source_top - desired_top)
        patch = previous.crop((source_left, source_top, source_right, source_bottom))
        output.paste(patch, destination)
        valid.paste(255, (destination[0], destination[1], destination[0] + patch.width, destination[1] + patch.height))
    return output, valid


def local_candidates(
    previous: Image.Image,
    current: Image.Image,
    predicted_x: float,
    predicted_y: float,
    camera_dx: float,
    camera_dy: float,
    radius: float,
) -> list[tuple[float, float, float]]:
    """Return bright, temporally changed local maxima in current source pixels."""
    width, height = current.size
    bounds = crop_bounds(predicted_x, predicted_y, radius, width, height)
    left, top, right, bottom = bounds
    current_roi = current.crop(bounds)
    # The previous ROI shifts opposite the measured image translation so static
    # scene texture is discounted before local peak selection.
    previous_roi, valid_overlap = translated_previous_roi(previous, bounds, camera_dx, camera_dy)
    highpass = ImageChops.subtract(current_roi, current_roi.filter(ImageFilter.GaussianBlur(PARAMETERS["gaussian_radius_px"])))
    temporal = ImageChops.multiply(ImageChops.difference(current_roi, previous_roi), valid_overlap)
    response = ImageChops.add(highpass, temporal, scale=1.5)
    work = response.copy()
    detections: list[tuple[float, float, float]] = []
    for _ in range(PARAMETERS["maximum_candidates_per_frame"]):
        maximum = maximum_pixel(work)
        if maximum is None or maximum[2] < PARAMETERS["minimum_combined_response"]:
            break
        ix, iy, peak = maximum
        x, y = float(ix), float(iy)
        highpass_value, temporal_value = highpass.getpixel((ix, iy)), temporal.getpixel((ix, iy))
        confidence = min(1.0, peak / 255.0)
        if (highpass_value >= PARAMETERS["minimum_highpass"]
                and temporal_value >= PARAMETERS["minimum_temporal_difference"]
                and confidence >= PARAMETERS["minimum_confidence"]):
            detections.append((left + x, top + y, confidence))
        draw = ImageDraw.Draw(work)
        suppression = PARAMETERS["candidate_suppression_radius_px"]
        draw.ellipse((x - suppression, y - suppression, x + suppression, y + suppression), fill=0)
    return detections


def choose_candidate(candidates: list[tuple[float, float, float]], predicted_x: float, predicted_y: float, radius: float) -> tuple[float, float, float] | None:
    if not candidates:
        return None
    # Local detector response is favoured, with a bounded distance preference
    # that does not manufacture positions when no image peak exists.
    return max(candidates, key=lambda item: (item[2] - 0.25 * math.hypot(item[0] - predicted_x, item[1] - predicted_y) / radius, item[2]))


def tracker(config: dict[str, Any]) -> dict[str, Any]:
    if "parameters" in config:
        raise ValueError("Per-clip parameter overrides are not permitted")
    metadata = source_metadata(config)
    width, height = metadata["width"], metadata["height"]
    frames = load_frames(manifest_path(config), metadata)
    seed_time, seed_x, seed_y = pixel_seed(config, width, height)
    seed_index = min(range(len(frames)), key=lambda index: abs(frames[index].timestamp - seed_time))
    if abs(frames[seed_index].timestamp - seed_time) > PARAMETERS["seed_timestamp_tolerance_seconds"]:
        raise ValueError("Seed timestamp must equal an AVFoundation cache source PTS")

    started = time.perf_counter()
    previous = luminance(frames[seed_index].file, (width, height))
    last_x, last_y, last_time = seed_x, seed_y, frames[seed_index].timestamp
    velocity_x: float | None = None
    velocity_y: float | None = None
    misses = 0
    observations: list[Observation] = []
    candidate_pool: list[Observation] = []
    diagnostics: list[dict[str, Any]] = [{
        "timestamp": frames[seed_index].timestamp,
        "outcome": "seed-constraint",
        "candidateCount": 0,
        "seedCoordinateEmitted": False,
    }]
    processed = 0
    terminated = "end-of-cache"

    for frame in frames[seed_index + 1:]:
        current = luminance(frame.file, (width, height))
        processed += 1
        dt = frame.timestamp - last_time
        if dt <= 0:
            raise ValueError("Source PTS must increase")
        camera_dx, camera_dy = translation(previous, current, width, height)
        predicted_x = last_x + camera_dx + (velocity_x or 0.0) * dt
        predicted_y = last_y + camera_dy + (velocity_y or 0.0) * dt
        predicted_x = min(width - 1.0, max(0.0, predicted_x))
        predicted_y = min(height - 1.0, max(0.0, predicted_y))
        radius = min(PARAMETERS["maximum_roi_radius_px"], PARAMETERS["roi_radius_px"] * (1 + 0.35 * misses))
        local = local_candidates(previous, current, predicted_x, predicted_y, camera_dx, camera_dy, radius)
        candidate_pool.extend(
            Observation(frame.timestamp, x / width, y / height, confidence)
            for x, y, confidence in local
        )
        candidate = choose_candidate(local, predicted_x, predicted_y, radius)
        previous = current
        if candidate is None:
            misses += 1
            diagnostics.append({
                "timestamp": frame.timestamp,
                "outcome": "missing-local-observation",
                "candidateCount": len(local),
                "searchRadiusPx": radius,
                "cameraTranslationMagnitudePx": math.hypot(camera_dx, camera_dy),
            })
            if misses >= PARAMETERS["maximum_misses"]:
                terminated = "consecutive-local-observation-misses"
                break
            continue
        x, y, confidence = candidate
        observed_dt = frame.timestamp - last_time
        velocity_x, velocity_y = (x - last_x) / observed_dt, (y - last_y) / observed_dt
        last_x, last_y, last_time = x, y, frame.timestamp
        misses = 0
        observations.append(Observation(frame.timestamp, x / width, y / height, confidence))
        diagnostics.append({
            "timestamp": frame.timestamp,
            "outcome": "observed-local-candidate",
            "candidateCount": len(local),
            "searchRadiusPx": radius,
            "cameraTranslationMagnitudePx": math.hypot(camera_dx, camera_dy),
        })

    payload = {
        "schemaVersion": "1.0",
        **metadata,
        "mode": "assisted",
        "promptCount": 1,
        "correctionCount": 0,
        "frames": [{"timestamp": item.timestamp, "x": item.x, "y": item.y, "detectorConfidence": item.confidence} for item in observations],
        "candidates": [{"timestamp": item.timestamp, "x": item.x, "y": item.y, "detectorConfidence": item.confidence} for item in candidate_pool],
        "diagnostics": diagnostics,
        "assistance": {
            "pointPromptCount": 1,
            "seedSourceTime": seed_time,
            "seedCoordinateEmitted": False,
            "interpretation": "One supplied first-visible source point seeds local temporal association; no label, crop trajectory, or physics continuation is used.",
        },
        "tracker": {
            "kind": "native-point-temporal-bright-object-v1",
            "parameters": PARAMETERS,
            "seedCacheTimestamp": frames[seed_index].timestamp,
            "sourceFrameCount": len(frames),
            "processedAfterSeedFrameCount": processed,
            "observedFrameCount": len(observations),
            "candidateCount": len(candidate_pool),
            "termination": terminated,
            "elapsedWallSeconds": time.perf_counter() - started,
            "frameManifestSHA256": hashlib.sha256(manifest_path(config).read_bytes()).hexdigest(),
        },
    }
    return payload


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True, help="external private native-point configuration")
    parser.add_argument("--output", type=Path, required=True, help="external private prediction JSON")
    args = parser.parse_args()
    try:
        config_path = outside(args.config, "Configuration")
        output_path = outside(args.output, "Prediction output")
        result = tracker(json.loads(config_path.read_text()))
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(result, indent=2) + "\n")
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as error:
        # Never include private file paths, media coordinates, or labels in logs.
        parser.exit(2, f"Native point tracker failed ({type(error).__name__}); verify the private frame cache and configuration.\n")
    print(f"Native point tracker wrote {len(result['frames'])} observed positions; termination={result['tracker']['termination']}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
