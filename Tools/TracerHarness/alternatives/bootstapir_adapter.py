#!/usr/bin/env python3
"""Run the official offline BootsTAPIR model on private local source video.

No network requests, model downloads, fitting, retiming, or app integration occur
in this adapter. Supply an external checkout, checkpoint, private configuration,
and output path. Frame indices are zero-based decoded source-frame indices.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import math
import os
from pathlib import Path
import platform
import subprocess
import sys
import time


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def external_path(path: str | Path, repository_root: Path, kind: str) -> Path:
    """Reject private paths inside the checkout, including symlink targets."""
    resolved = Path(path).expanduser().resolve()
    if resolved.is_relative_to(repository_root):
        raise ValueError(f"{kind} must be outside the repository")
    return resolved


def run() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--tapnet-root", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--device", choices=("cpu", "mps"), default="mps")
    parser.add_argument("--max-frames", type=int)
    parser.add_argument("--feature-chunk-size", type=int, default=4)
    args = parser.parse_args()
    repository_root = Path(__file__).resolve().parents[3]
    try:
        args.output = external_path(args.output, repository_root, "Prediction output")
        args.checkpoint = external_path(args.checkpoint, repository_root, "Model checkpoint")
        args.config = external_path(args.config, repository_root, "Private configuration")
    except ValueError as error:
        parser.error(str(error))
    if args.max_frames is not None and args.max_frames < 2:
        parser.error("--max-frames must be at least 2")
    if args.feature_chunk_size < 1:
        parser.error("--feature-chunk-size must be positive")

    started = time.perf_counter()
    config = json.loads(args.config.read_text())
    source = external_path(config["source_path"], repository_root, "Source media")
    cache_path = (external_path(config["frame_cache_manifest"], repository_root, "Frame cache manifest")
                  if config.get("frame_cache_manifest") else None)
    av_manifest_path = (external_path(config["avfoundation_frame_manifest"], repository_root,
                                      "Source timestamp manifest")
                        if config.get("avfoundation_frame_manifest") else None)
    sys.path.insert(0, str(args.tapnet_root.resolve()))
    import av
    import numpy as np
    from PIL import Image
    import torch
    from tapnet.torch import tapir_model

    resolution = tuple(config.get("model_input_size", [512, 512]))
    if len(resolution) != 2 or any(v < 256 or v % 8 for v in resolution):
        raise ValueError("model_input_size must be [width,height], each >=256 and divisible by 8")
    crop = tuple(config["crop_xywh"])
    if len(crop) != 4 or any(int(v) != v for v in crop) or min(crop[2:]) <= 0:
        raise ValueError("crop_xywh must contain integer x,y,width,height")
    start = float(config.get("start_time_seconds", 0))
    end = float(config.get("end_time_seconds", math.inf))
    if not 0 <= start < end:
        raise ValueError("Require 0 <= start_time_seconds < end_time_seconds")
    prompts = config["prompts"]
    if len(prompts) != 1:
        raise ValueError("This comparison adapter accepts exactly one point prompt, not correction fusion")
    if config.get("correction_count", 0) != 0:
        raise ValueError("Correction fusion is not implemented; correction_count must be zero")

    # A static source crop avoids adding artificial crop motion to the model.
    # Rotation is explicit, never inferred from the target's predicted location.
    rotation = int(config.get("rotation_ccw_degrees", 0))
    if rotation not in (0, 90, 180, 270):
        raise ValueError("rotation_ccw_degrees must be 0,90,180,270")
    frames, times, indices, ticks = [], [], [], []
    decoded_times = []
    width = height = None
    with av.open(str(source)) as container:
        stream = container.streams.video[0]
        encoded_size = [stream.codec_context.width, stream.codec_context.height]
    decoder = "PyAV"
    if cache_path:
        decoder = "AVFoundation source-frame PNG cache"
        cache = json.loads(cache_path.read_text())
        width, height = cache["width"], cache["height"]
        if rotation:
            raise ValueError("AVFoundation cache must already have the preferred transform applied")
        for record in cache["frames"]:
            source_time = float(record["timestamp"])
            if source_time < start or source_time > end:
                continue
            x,y,w,h = crop
            left,top = x-record["cropX"], y-record["cropY"]
            if (left < 0 or top < 0 or left+w > record["cropWidth"]
                    or top+h > record["cropHeight"]):
                raise ValueError("Requested source crop is not fully contained in the cached frame")
            frame_path = external_path(cache_path.parent/record["file"], repository_root,
                                       "Cached source frame")
            with Image.open(frame_path) as image:
                patch = image.convert("RGB").crop((left,top,left+w,top+h))
                if patch.size != resolution:
                    patch = patch.resize(resolution, Image.Resampling.BILINEAR)
                frames.append(np.asarray(patch))
            times.append(source_time)
            indices.append(record["frameIndex"])
            ticks.append({"timestamp_origin":"AVFoundation manifest"})
            if args.max_frames and len(frames) >= args.max_frames:
                break
    else:
        with av.open(str(source)) as container:
            stream = container.streams.video[0]
            for index, frame in enumerate(container.decode(stream)):
                if frame.pts is None:
                    raise ValueError("Missing source frame PTS: no synthetic times are allowed")
                source_time = float(frame.pts * frame.time_base)
                if decoded_times and source_time <= decoded_times[-1]:
                    raise ValueError("Source PTS must be strictly increasing")
                decoded_times.append(source_time)
                if source_time < start:
                    continue
                if source_time > end:
                    break
                array = frame.to_ndarray(format="rgb24")
                if rotation:
                    array = np.rot90(array, rotation // 90)
                height, width = array.shape[:2]
                x, y, w, h = crop
                if x < 0 or y < 0 or x + w > width or y + h > height:
                    raise ValueError("Crop falls outside the upright source frame")
                patch = Image.fromarray(array[y:y+h, x:x+w])
                if patch.size != resolution:
                    patch = patch.resize(resolution, Image.Resampling.BILINEAR)
                frames.append(np.asarray(patch))
                times.append(source_time)
                indices.append(index)
                ticks.append({"value": frame.pts, "time_base_numerator": frame.time_base.numerator,
                              "time_base_denominator": frame.time_base.denominator})
                if args.max_frames and len(frames) >= args.max_frames:
                    break
    if len(frames) < 2:
        raise ValueError("Selected interval contains fewer than two frames")
    if any(b <= a for a,b in zip(times,times[1:])):
        raise ValueError("Selected source PTS are not strictly increasing")
    if any(b != a+1 for a,b in zip(indices,indices[1:])):
        raise ValueError("Selected frames are not consecutive source frames")

    av_manifest_check = None
    if av_manifest_path:
        manifest = json.loads(av_manifest_path.read_text())
        reference_times = manifest["frameTimes"]
        differences = [abs(reference_times[i] - t) for i, t in zip(indices, times)]
        av_manifest_check = {"compared_frame_count": len(times),
                             "maximum_absolute_time_difference_seconds": max(differences)}
        if max(differences) > 1e-6:
            raise ValueError(f"PyAV/AVFoundation source PTS disagree: {av_manifest_check}")

    queries, actual_prompts = [], []
    for prompt in prompts:
        requested = float(prompt["time_seconds"])
        local_index = min(range(len(times)), key=lambda i: abs(times[i] - requested))
        if abs(times[local_index] - requested) > 0.025:
            raise ValueError("Prompt must be within 25ms of a selected source frame")
        px, py = float(prompt["x_px"]), float(prompt["y_px"])
        if not crop[0] <= px < crop[0]+crop[2] or not crop[1] <= py < crop[1]+crop[3]:
            raise ValueError("Prompt is outside the source crop")
        queries.append([local_index, (py-crop[1])*resolution[1]/crop[3],
                        (px-crop[0])*resolution[0]/crop[2]])
        actual_prompts.append({**prompt, "actual_source_time_seconds": times[local_index],
                               "source_frame_index": indices[local_index],
                               "model_query_tyx": queries[-1]})

    decoded_at = time.perf_counter()
    print(json.dumps({"stage": "decoded", "frames": len(frames), "source_size": [width,height],
                      "crop_size": crop[2:], "model_input_size": resolution,
                      "seconds": decoded_at-started, "av_manifest_check": av_manifest_check}), flush=True)
    if args.device == "mps" and not torch.backends.mps.is_available():
        raise RuntimeError("MPS requested but unavailable; explicitly select --device cpu to retry")
    model = tapir_model.TAPIR(pyramid_level=1,
                             feature_extractor_chunk_size=args.feature_chunk_size)
    model.load_state_dict(torch.load(args.checkpoint, map_location="cpu", weights_only=True))
    model = model.to(args.device).eval()
    video = torch.from_numpy(np.stack(frames)).to(args.device).float()[None]/255*2-1
    queries_tensor = torch.tensor(queries, dtype=torch.float32, device=args.device)[None]
    del frames
    if args.device == "mps":
        torch.mps.synchronize()
    inference_start = time.perf_counter()
    print(json.dumps({"stage": "model_ready", "device": args.device,
                      "seconds": inference_start-decoded_at}), flush=True)
    with torch.inference_mode():
        predictions = model(video, queries_tensor, query_chunk_size=1)
    if args.device == "mps":
        torch.mps.synchronize()
    inference_end = time.perf_counter()
    tracks = predictions["tracks"][0].cpu().numpy()
    occlusion = predictions["occlusion"][0].cpu().numpy()
    expected_dist = predictions["expected_dist"][0].cpu().numpy()
    confidence = ((1-torch.sigmoid(predictions["occlusion"][0])) *
                  (1-torch.sigmoid(predictions["expected_dist"][0]))).cpu().numpy()
    if not all(np.isfinite(a).all() for a in (tracks,occlusion,expected_dist,confidence)):
        raise RuntimeError("Model returned non-finite predictions")
    model_tracks = []
    for query_index in range(len(prompts)):
        samples = []
        for j, (tx,ty) in enumerate(tracks[query_index]):
            px = float(tx)*crop[2]/resolution[0]+crop[0]
            py = float(ty)*crop[3]/resolution[1]+crop[1]
            samples.append({"frame_index": indices[j], "source_time_seconds": times[j],
                            "source_pts": ticks[j], "x_normalised": px/width,
                            "y_normalised": py/height, "x_px": px, "y_px": py,
                            "visible": bool(confidence[query_index,j] > 0.5),
                            "confidence": float(confidence[query_index,j]),
                            "occlusion_logit": float(occlusion[query_index,j]),
                            "expected_distance_logit": float(expected_dist[query_index,j])})
        model_tracks.append({"query_index":query_index, "samples":samples})
    upstream_commit = subprocess.check_output(
        ["git","-C",str(args.tapnet_root),"rev-parse","HEAD"],text=True).strip()
    source_hash = digest(source)
    result = {
        "schemaVersion": "1.0", "clipId": config["clip_id"],
        "sourceHash": "sha256:"+source_hash, "width":width,"height":height,
        "coordinateOrigin":"top-left","coordinateSpace":"normalized",
        "mode":"assisted","promptCount":len(prompts),"correctionCount":0,
        "frames":[{"timestamp":sample["source_time_seconds"],
                   "x":sample["x_normalised"],"y":sample["y_normalised"],
                   "confidence":sample["confidence"]}
                  for sample in model_tracks[0]["samples"] if sample["visible"]],
        "schema_version": "ronde-alternative-track-1", "clip_id": config["clip_id"],
        "model": "official_bootstapir_v2_offline", "upstream_commit": upstream_commit,
        "checkpoint_sha256": digest(args.checkpoint), "licence": "Apache-2.0 code and checkpoint",
        "source": {"filename":source.name,"sha256":source_hash,"width":width,"height":height,
                   "encoded_size":encoded_size,"rotation_ccw_degrees":rotation},
        "coordinate_space": "upright_source_normalised_top_left_x_over_width_y_over_height",
        "assistance": {"prompt_count":len(prompts),"prompts":actual_prompts,
                       "crop_xywh":crop,"crop_type":config["crop_type"],
                       "crop_rationale":config["crop_rationale"],
                       "temporal_interval_supplied":True,"uses_future_frames":True,
                       "correction_count":int(config.get("correction_count",0))},
        "processing": {"device":args.device,"platform":platform.platform(),"decoder":decoder,
                       "mps_fallback_enabled":os.environ.get("PYTORCH_ENABLE_MPS_FALLBACK")=="1",
                       "model_parameter_dtype":str(next(model.parameters()).dtype),
                       "model_parameter_count":sum(p.numel() for p in model.parameters()),
                       "python":platform.python_version(),"torch":torch.__version__,
                       "numpy":np.__version__,"av":importlib.metadata.version("av"),
                       "model_input_size":resolution,"feature_chunk_size":args.feature_chunk_size,
                       "selected_frame_count":len(times),"source_frame_subsampling":False,
                       "source_time_start":times[0],"source_time_end":times[-1],
                       "av_manifest_check":av_manifest_check,"visibility_threshold":0.5,
                       "confidence_interpretation":"Upstream occlusion/expected-error product; not calibrated golf correctness",
                       "decode_and_setup_seconds":decoded_at-started,
                       "model_load_seconds":inference_start-decoded_at,
                       "inference_seconds":inference_end-inference_start,
                       "wall_seconds_before_serialisation":time.perf_counter()-started},
        "tracks":model_tracks,
    }
    if len(model_tracks)==1:
        result["samples"] = model_tracks[0]["samples"]
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2)+"\n")
    print(json.dumps({"stage":"complete","frames":len(times),
                      "inference_seconds":inference_end-inference_start,
                      "visible_frames_per_query":[int((c>0.5).sum()) for c in confidence],
                      "output":str(args.output)}),flush=True)


if __name__ == "__main__":
    run()
