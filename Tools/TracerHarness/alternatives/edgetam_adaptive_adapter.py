#!/usr/bin/env python3
"""Bounded single-point EdgeTAM experiment with model-centred fixed crop segments.

This is a private research adapter, not a production tracking policy. It stops
each direction on its first empty/invalid mask and never invents coordinates.
"""
from __future__ import annotations

import argparse
import importlib.metadata
import json
import math
from pathlib import Path
import platform
import signal
import subprocess
import sys
import time

from edgetam_adapter import digest, external


PARAMETERS = {
    "cropSize": 512,
    "innerMinimum": 128,
    "innerMaximumExclusive": 384,
    "maximumAutomaticReseeds": 32,
    "maximumPropagationSeconds": 240,
    "emptyMaskPolicy": "stop direction immediately",
    "maskRule": "logits > 0; largest 8-connected component; unweighted pixel-centre centroid",
    "transitionObservationPolicy": "preserve old-crop canonical observation; new seed mask is diagnostic only",
}


class BudgetExceeded(RuntimeError):
    pass


class InvalidObservation(RuntimeError):
    pass


def violating_axis_can_recenter(local_x, local_y, old_crop, new_crop):
    """A clamped axis must not cause resets through unrelated-axis drift."""
    x_violates = not 128 <= local_x < 384
    y_violates = not 128 <= local_y < 384
    return ((x_violates and new_crop[0] != old_crop[0])
            or (y_violates and new_crop[1] != old_crop[1]))


def gap_continuation_decision(last_observed_time, current_time, maximum_gap_seconds=0.0):
    """A propagated empty mask can only retain state/crop, never emit a point."""
    elapsed = (abs(current_time - last_observed_time)
               if last_observed_time is not None else None)
    allowed = (maximum_gap_seconds > 0 and elapsed is not None
               and elapsed <= maximum_gap_seconds + 1e-9)
    return {"continueSameStateAndCrop": allowed, "emitPoint": False,
            "recenter": False, "elapsedSourceSeconds": elapsed}


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("config", "edgetam-root", "checkpoint", "output"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--device", choices=("mps", "cpu"), default="mps")
    args = parser.parse_args()
    started = time.perf_counter()
    code_sha = digest(Path(__file__))
    helper_sha = digest(Path(__file__).with_name("edgetam_adapter.py"))
    config_path, upstream, checkpoint, output = map(external,
        (args.config, args.edgetam_root, args.checkpoint, args.output))
    if output.exists():
        raise ValueError("Refuse to overwrite an existing experiment result")
    config = json.loads(config_path.read_text())
    if config["parameters"] != PARAMETERS:
        raise ValueError("Configuration must match the frozen experiment parameters")
    maximum_gap_seconds = config.get("source_time_gap_seconds", 0.0)
    if type(maximum_gap_seconds) not in (int, float) or maximum_gap_seconds not in (0.0, 0.20):
        raise ValueError("Only default first-empty or the explicit 0.20 s gap variant is supported")
    cache_path = external(config["frame_cache_manifest"])
    av_path = external(config["avfoundation_frame_manifest"])
    source_path = external(config["source_path"])
    cache = json.loads(cache_path.read_text())
    av = json.loads(av_path.read_text())
    width, height = cache["width"], cache["height"]
    if (width, height) != (av["width"], av["height"]) or min(width, height) < 512:
        raise ValueError("Full-source upright dimensions do not match")
    if cache.get("coordinateOrigin") != "top-left":
        raise ValueError("Full-source cache must declare top-left coordinates")
    frames = [f for f in cache["frames"]
              if config["start_time_seconds"] <= f["timestamp"] <= config["end_time_seconds"]]
    expected = [(i, t) for i, t in enumerate(av["frameTimes"])
                if config["start_time_seconds"] <= t <= config["end_time_seconds"]]
    if [(f["frameIndex"], f["timestamp"]) for f in frames] != expected:
        raise ValueError("Full cache must contain every exact source PTS in the interval")
    for f in frames:
        if (f["cropX"], f["cropY"], f["cropWidth"], f["cropHeight"]) != (0, 0, width, height):
            raise ValueError("An oracle corridor or partial source cache is unsupported")
        external(cache_path.parent / f["file"])
    if len(config["prompts"]) != 1 or config.get("correction_count", 0) != 0:
        raise ValueError("Exactly one supplied point and no correction are allowed")
    prompt = config["prompts"][0]
    if not all(math.isfinite(prompt[k]) for k in ("x_px", "y_px", "time_seconds")):
        raise ValueError("Supplied point must be finite")
    if not 0 <= prompt["x_px"] < width or not 0 <= prompt["y_px"] < height:
        raise ValueError("Supplied point is outside the upright source")
    seed = min(range(len(frames)), key=lambda i: abs(frames[i]["timestamp"] - prompt["time_seconds"]))
    if abs(frames[seed]["timestamp"] - prompt["time_seconds"]) > .001:
        raise ValueError("Supplied point must match source PTS within 1 ms")

    sys.path.insert(0, str(upstream))
    import numpy as np
    from PIL import Image
    from scipy import ndimage
    import torch
    import sam2.sam2_video_predictor as predictor_module
    import sam2.modeling.backbones.timm as backbone_module
    from sam2.build_sam import build_sam2_video_predictor

    if args.device == "mps" and not torch.backends.mps.is_available():
        raise RuntimeError("MPS requested but unavailable")
    original_create_model = backbone_module.create_model

    def local_backbone(*values, **kwargs):
        kwargs["pretrained"] = False
        return original_create_model(*values, **kwargs)

    backbone_module.create_model = local_backbone
    overrides = [
        "++model.sam_mask_decoder_extra_args.dynamic_multimask_via_stability=true",
        "++model.sam_mask_decoder_extra_args.dynamic_multimask_stability_delta=0.05",
        "++model.sam_mask_decoder_extra_args.dynamic_multimask_stability_thresh=0.98",
        "++model.binarize_mask_from_pts_for_mem_enc=true",
        "++model.fill_hole_area=0",
    ]
    try:
        predictor = build_sam2_video_predictor("configs/edgetam.yaml", str(checkpoint),
            device=args.device, apply_postprocessing=False, hydra_overrides_extra=overrides)
    finally:
        backbone_module.create_model = original_create_model
    if predictor.fill_hole_area != 0 or predictor.image_size != 1024:
        raise ValueError("Unexpected model configuration")

    output.parent.mkdir(parents=True, exist_ok=True)
    mask_dir = external(output.parent / (output.stem + "-masks"))
    mask_dir.mkdir(exist_ok=True)
    samples, segments, transitions, initial_comparisons, gap_events = {}, [], [], [], []
    endings, automatic_reseeds = {}, 0
    original_loader = predictor_module.load_video_frames
    propagation_start = time.perf_counter()

    def check_budget():
        if time.perf_counter() - propagation_start >= PARAMETERS["maximumPropagationSeconds"]:
            raise BudgetExceeded("propagation_time_limit")

    def alarm_handler(signum, frame):
        raise BudgetExceeded("propagation_time_limit")

    def crop_for(x, y):
        return (min(max(0, math.floor(x + .5) - 256), width - 512),
                min(max(0, math.floor(y + .5) - 256), height - 512), 512, 512)

    class LosslessFrames:
        def __init__(self, crop):
            self.crop = crop

        def __len__(self):
            return len(frames)

        def __getitem__(self, index):
            f = frames[index]
            x, y, w, h = self.crop
            with Image.open(external(cache_path.parent / f["file"])) as im:
                if im.size != (width, height):
                    raise ValueError("Cached source image dimensions differ from manifest")
                im = im.convert("RGB").crop((x, y, x + w, y + h))
                im = im.resize((1024, 1024), Image.Resampling.BICUBIC)
                tensor = torch.from_numpy(np.asarray(im).copy()).permute(2, 0, 1).float() / 255.0
            return (tensor - torch.tensor([.485, .456, .406])[:, None, None]) / torch.tensor([.229, .224, .225])[:, None, None]

    def capture(index, logits, state, direction, crop, segment_id, kind):
        values = logits[0, 0].detach().float().cpu().numpy()
        if values.shape != (512, 512) or not np.isfinite(values).all():
            np.save(mask_dir / f"invalid-{direction}-{segment_id}-{index}.npy", values)
            raise InvalidObservation("nonfinite_or_malformed_mask")
        foreground = values > 0
        labels, count = ndimage.label(foreground, np.ones((3, 3), dtype=np.uint8))
        areas = np.bincount(labels.ravel())
        areas[0] = 0
        component = int(areas.argmax()) if count else 0
        f = frames[index]
        record = {"timestamp": f["timestamp"], "sourceFrameIndex": f["frameIndex"],
            "visible": bool(component), "processingStatus": "observed_mask" if component else "empty_mask",
            "crop_xywh": list(crop), "segmentId": segment_id, "direction": direction,
            "componentCount": int(count), "rawPositiveMaskAreaPx": int(foreground.sum()),
            "selectedComponentAreaPx": int(areas[component]) if component else 0,
            "maximumMaskLogit": float(values.max())}
        stored = state["output_dict"]["cond_frame_outputs"].get(index)
        if stored is None:
            stored = state["output_dict"]["non_cond_frame_outputs"].get(index)
        if stored is not None and "object_score_logits" in stored:
            logit = float(stored["object_score_logits"].detach().float().cpu().flatten()[0])
            record.update(objectScoreLogit=logit, confidence=1 / (1 + math.exp(-max(-80, min(80, logit)))))
        if component:
            ys, xs = np.nonzero(labels == component)
            x, y = float(xs.mean() + .5 + crop[0]), float(ys.mean() + .5 + crop[1])
            if not 0 <= x < width or not 0 <= y < height:
                raise InvalidObservation("centroid_outside_source")
            record.update(x=x / width, y=y / height,
                touchesCropEdge=bool((xs == 0).any() or (xs == 511).any() or (ys == 0).any() or (ys == 511).any()),
                meanComponentMaskLogit=float(values[labels == component].mean()))
        mask_path = external(mask_dir / f"{kind}-{direction}-s{segment_id:03d}-f{f['frameIndex']:04d}.png")
        Image.fromarray(foreground.astype(np.uint8) * 255).save(mask_path)
        record["rawBinaryMaskPath"] = str(mask_path)
        return record

    signal.signal(signal.SIGALRM, alarm_handler)
    signal.setitimer(signal.ITIMER_REAL, PARAMETERS["maximumPropagationSeconds"])
    direction = "forward"
    print(json.dumps({"stage": "model_ready", "sourceFrames": len(frames), "modelInputSize": 1024,
                      "maximumAutomaticReseeds": 32, "maximumPropagationSeconds": 240}), flush=True)
    try:
        with torch.inference_mode():
            for reverse in (False, True):
                direction = "reverse" if reverse else "forward"
                step = -1 if reverse else 1
                anchor = seed
                point = (prompt["x_px"], prompt["y_px"])
                crop = crop_for(*point)
                pending_transition = None
                last_observed_time = None
                active_gap = None
                while True:
                    check_budget()
                    if pending_transition is not None:
                        automatic_reseeds += 1
                    segment_id = len(segments)
                    segments.append({"segmentId": segment_id, "direction": direction, "crop_xywh": list(crop),
                        "anchorTimestamp": frames[anchor]["timestamp"], "anchorSourceFrameIndex": frames[anchor]["frameIndex"],
                        "pointSource": "model_centroid" if pending_transition is not None else "single_user_point"})
                    images = LosslessFrames(crop)
                    predictor_module.load_video_frames = lambda **kwargs: (images, 512, 512)
                    state = predictor.init_state("private-fullsource-av-cache", offload_video_to_cpu=True,
                                                 offload_state_to_cpu=False)
                    predictor.add_new_points_or_box(state, frame_idx=anchor, obj_id=1,
                        points=np.array([[point[0] - crop[0], point[1] - crop[1]]], dtype=np.float32),
                        labels=np.array([1], dtype=np.int32))
                    iterator = predictor.propagate_in_video(state, start_frame_idx=anchor, reverse=reverse)
                    next_segment = None
                    previous_record = None
                    try:
                        for expected_index in range(anchor, -1 if reverse else len(frames), step):
                            check_budget()
                            # Check the source-time limit before asking the model
                            # to process the next frame, including irregular PTS.
                            if active_gap is not None and not gap_continuation_decision(
                                    last_observed_time, frames[expected_index]["timestamp"],
                                    maximum_gap_seconds)["continueSameStateAndCrop"]:
                                endings[direction] = {"reason": "source_time_gap_limit",
                                    "firstUnprocessedTimestamp": frames[expected_index]["timestamp"],
                                    "lastObservedTimestamp": last_observed_time}
                                active_gap["terminationReason"] = "source_time_gap_limit"
                                active_gap["firstUnprocessedTimestamp"] = frames[expected_index]["timestamp"]
                                break
                            index, ids, logits = next(iterator)
                            if index != expected_index:
                                raise RuntimeError("Predictor source-frame order changed")
                            is_transition = index == anchor and pending_transition is not None
                            duplicate_initial = index == seed and reverse and pending_transition is None
                            kind = "transition" if is_transition else "initial-reverse" if duplicate_initial else "canonical"
                            try:
                                record = capture(index, logits, state, direction, crop, segment_id, kind)
                            except InvalidObservation as exc:
                                endings[direction] = {"reason": str(exc), "timestamp": frames[index]["timestamp"]}
                                if not is_transition and not duplicate_initial:
                                    samples[index] = {"timestamp": frames[index]["timestamp"],
                                        "sourceFrameIndex": frames[index]["frameIndex"], "visible": False,
                                        "processingStatus": "invalid_mask", "reason": str(exc), "direction": direction}
                                break
                            if is_transition:
                                pending_transition["newSeedMask"] = record
                                if record["visible"]:
                                    pending_transition["centroidDisagreementPx"] = math.hypot(
                                        record["x"] * width - point[0], record["y"] * height - point[1])
                                else:
                                    endings[direction] = {"reason": "empty_reseed_mask", "timestamp": record["timestamp"]}
                                    break
                                previous_record = record
                                continue
                            if duplicate_initial:
                                initial_comparisons.append(record)
                            else:
                                if index in samples:
                                    raise RuntimeError("Attempted to replace a canonical observation")
                                if previous_record is not None and previous_record["visible"] and record["visible"]:
                                    record["stepDisplacementPx"] = math.hypot((record["x"] - previous_record["x"]) * width,
                                                                              (record["y"] - previous_record["y"]) * height)
                                samples[index] = record
                            previous_record = record
                            if not record["visible"]:
                                decision = gap_continuation_decision(last_observed_time,
                                    record["timestamp"], maximum_gap_seconds)
                                if decision["continueSameStateAndCrop"]:
                                    if active_gap is None:
                                        active_gap = {"direction": direction, "lastObservedTimestamp": last_observed_time,
                                            "firstEmptyTimestamp": record["timestamp"], "crop_xywh": list(crop),
                                            "segmentId": segment_id, "emptyFrameTimestamps": []}
                                        gap_events.append(active_gap)
                                    active_gap["emptyFrameTimestamps"].append(record["timestamp"])
                                    record["gapContinuation"] = decision
                                    if not 0 <= index + step < len(frames):
                                        endings[direction] = {"reason": "interval_boundary_after_empty",
                                            "timestamp": record["timestamp"]}
                                        active_gap["terminationReason"] = "interval_boundary_after_empty"
                                        break
                                    # No recenter, reseed, point or replacement
                                    # is allowed on an empty source frame.
                                    continue
                                endings[direction] = {"reason": "first_empty_mask", "timestamp": record["timestamp"]}
                                break
                            if active_gap is not None:
                                active_gap["recoveredTimestamp"] = record["timestamp"]
                                active_gap["recoveredMaskPath"] = record["rawBinaryMaskPath"]
                                active_gap["elapsedSinceLastObservedSeconds"] = abs(record["timestamp"] - last_observed_time)
                                record["recoveredAfterEmptyFrames"] = len(active_gap["emptyFrameTimestamps"])
                                active_gap = None
                            last_observed_time = record["timestamp"]
                            if not 0 <= index + step < len(frames):
                                endings[direction] = {"reason": "interval_boundary", "timestamp": record["timestamp"]}
                                break
                            x, y = record["x"] * width, record["y"] * height
                            local_x, local_y = x - crop[0], y - crop[1]
                            if not (128 <= local_x < 384 and 128 <= local_y < 384):
                                new_crop = crop_for(x, y)
                                if not violating_axis_can_recenter(local_x, local_y, crop, new_crop):
                                    record["recenterBlockedBySourceEdge"] = True
                                    continue
                                if automatic_reseeds >= PARAMETERS["maximumAutomaticReseeds"]:
                                    endings[direction] = {"reason": "automatic_reseed_limit", "timestamp": record["timestamp"]}
                                    break
                                transition = {"direction": direction, "timestamp": record["timestamp"],
                                    "sourceFrameIndex": record["sourceFrameIndex"], "oldCrop": list(crop),
                                    "newCrop": list(new_crop), "modelDerivedPointPx": [x, y],
                                    "canonicalMaskPath": record["rawBinaryMaskPath"], "canonicalPreserved": True}
                                transitions.append(transition)
                                next_segment = (index, (x, y), new_crop, transition)
                                break
                    finally:
                        iterator.close()
                        del state
                    if next_segment is None:
                        break
                    anchor, point, crop, pending_transition = next_segment
            if args.device == "mps":
                torch.mps.synchronize()
    except BudgetExceeded:
        endings[direction] = {"reason": "propagation_time_limit"}
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        predictor_module.load_video_frames = original_loader
    finished = time.perf_counter()
    ordered = []
    for index, frame in enumerate(frames):
        if index not in samples:
            d = "reverse" if index < seed else "forward"
            samples[index] = {"timestamp": frame["timestamp"], "sourceFrameIndex": frame["frameIndex"],
                "visible": False, "processingStatus": "unprocessed_after_direction_stop", "direction": d,
                "reason": endings.get(d, {"reason": "not_started_after_time_limit"})["reason"]}
        ordered.append(samples[index])
    result = {"schemaVersion": "1.0", "clipId": config["clip_id"], "sourceHash": "sha256:" + digest(source_path),
        "width": width, "height": height, "coordinateOrigin": "top-left", "coordinateSpace": "normalized",
        "mode": "assisted", "promptCount": 1, "pointPromptCount": 1, "timingPromptCount": 0, "correctionCount": 0,
        "automaticReseedCount": automatic_reseeds,
        "initialDirectionalPromptApplications": sum(s["pointSource"] == "single_user_point" for s in segments),
        "frames": [{k: r[k] for k in ("timestamp", "x", "y", "confidence") if k in r} for r in ordered if r["visible"]],
        "samples": ordered, "segments": segments, "automaticTransitions": transitions,
        "initialReverseSeedMasks": initial_comparisons, "directionTermination": endings,
        "maximumSourceTimeGapSeconds": maximum_gap_seconds, "gapEvents": gap_events,
        "gapRecoveryCount": sum("recoveredTimestamp" in g for g in gap_events),
        "gapPolicy": {"enabled": maximum_gap_seconds > 0,
            "effectiveEmptyMaskPolicy": "hold same state and crop within source-time bound" if maximum_gap_seconds else PARAMETERS["emptyMaskPolicy"],
            "numericalBoundaryAllowanceSeconds": 1e-9, "emptyFramesEmitPoints": False,
            "initialOrReseedEmptyStillStops": True, "cropMovesDuringEmptyGap": False},
        "assistance": {"pointPrompt": prompt, "suppliedInterval": True, "usesFutureEvidence": True,
            "crop_type": "model_centred_fixed_512_segments", "oracleCorridorUsed": False,
            "automaticPointsAreModelDerived": True, "pointCorrections": 0},
        "parameters": {**PARAMETERS,
            "emptyMaskPolicy": "hold same state and crop within source-time bound" if maximum_gap_seconds else PARAMETERS["emptyMaskPolicy"],
            "maximumSourceTimeGapSeconds": maximum_gap_seconds}, "model": "official_EdgeTAM",
        "upstream_commit": subprocess.check_output(["git", "-C", str(upstream), "rev-parse", "HEAD"], text=True).strip(),
        "checkpoint_sha256": digest(checkpoint), "adapterCodeSHA256": code_sha,
        "configurationSHA256": digest(config_path), "fixedAdapterHelperSHA256": helper_sha,
        "fullSourceCacheManifestSHA256": digest(cache_path), "sourceAVManifestSHA256": digest(av_path),
        "processing": {"device": args.device, "platform": platform.platform(), "modelInputSize": [1024, 1024],
            "parameterDtype": str(next(predictor.parameters()).dtype), "fullSourceLosslessAVCache": True,
            "sourcePTSVerified": True, "inputResize": "Pillow bicubic; official ImageNet normalisation",
            "cudaHoleFillingDisabled": True, "noNewMotionAreaConfidenceGate": True,
            "setupSeconds": propagation_start - started, "propagationAndMaskExportSeconds": finished - propagation_start,
            "packageVersions": {name: importlib.metadata.version(name) for name in
                ("torch", "torchvision", "numpy", "pillow", "scipy", "timm", "hydra-core")}}}
    output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"stage": "complete", "sourceFrames": len(frames), "nonemptyMasks": len(result["frames"]),
        "automaticReseeds": automatic_reseeds, "propagationAndMaskExportSeconds": finished - propagation_start,
        "terminationReasons": {k: v["reason"] for k, v in endings.items()}}), flush=True)


if __name__ == "__main__":
    run()
